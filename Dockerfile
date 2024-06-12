FROM rockylinux/rockylinux:8
LABEL maintainer="tdockendorf@osc.edu; johrstrom@osc.edu"

ARG VERSION=latest
ARG CONCURRENCY=4
ENV PYTHON=/usr/libexec/platform-python

# setup the ondemand repositories
# RUN dnf -y install https://yum.osc.edu/ondemand/latest/ondemand-release-web-latest-1-6.noarch.rpm
# not working RUN dnf -y install https://yum.osc.edu/ondemand/latest/ondemand-release-compute-3.0-1.noarch.rpm

RUN dnf -y install https://yum.osc.edu/ondemand/latest/ondemand-release-web-latest-1-6.noarch.rpm && \
    sed -i 's|/latest/|/build/3.1/|g' /etc/yum.repos.d/ondemand-web.repo

# install all the dependencies
RUN dnf -y update && \
    dnf install -y dnf-utils && \
    dnf config-manager --set-enabled powertools && \
    dnf -y module enable nodejs:18 ruby:3.1 && \
    dnf install -y \
        file \
        lsof \
        sudo \
        gcc \
        gcc-c++ \
        git \
        patch \
        lua-posix \
        rsync \
        ondemand-gems \
        ondemand-runtime \
        ondemand-build \
        ondemand-apache \
        ondemand-ruby \
        ondemand-nodejs \
#       ondemand-python \
        ondemand-dex \
        ondemand-passenger \
        ondemand-nginx && \
    dnf clean all && rm -rf /var/cache/dnf/*

# vuln cleanup
# Verify Go installation
# Install Go
RUN dnf -y install wget && \
    wget https://go.dev/dl/go1.20.4.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.20.4.linux-amd64.tar.gz && \
    rm go1.20.4.linux-amd64.tar.gz && \
    export PATH=$PATH:/usr/local/go/bin

RUN go version

# Verify Node.js and npm installation
RUN node -v
RUN npm -v

# Update npm to the latest version
RUN npm install -g npm@latest

# Clear npm cache
RUN npm cache clean --force

# Install esbuild
RUN npm install esbuild@latest --verbose

# Verify esbuild installation
RUN ./node_modules/.bin/esbuild --version
# ---

RUN mkdir -p /opt/ood
RUN mkdir -p /var/www/ood/{apps,public,discover}
RUN mkdir -p /var/www/ood/apps/{sys,dev,usr}

COPY docker/launch-ood      /opt/ood/launch
COPY mod_ood_proxy          /opt/ood/mod_ood_proxy
COPY nginx_stage            /opt/ood/nginx_stage
COPY ood-portal-generator   /opt/ood/ood-portal-generator
COPY ood_auth_map           /opt/ood/ood_auth_map
COPY apps                   /opt/ood/apps
COPY Rakefile               /opt/ood/Rakefile
COPY lib                    /opt/ood/lib
COPY Gemfile                /opt/ood/Gemfile

RUN git clone https://github.com/andrejcermak/ood_core_extension.git /opt/ood/local_gems/ood_core

RUN cd /opt/ood; bundle install

RUN source /opt/rh/ondemand/enable
RUN cat /opt/ood/Rakefile
RUN rake -f /opt/ood/Rakefile -mj$CONCURRENCY build --trace
RUN mv /opt/ood/apps/* /var/www/ood/apps/sys/
RUN rm -rf /opt/ood/Rakefile /opt/ood/apps /opt/ood/lib

# copy configuration files
RUN mkdir -p /etc/ood/config
RUN cp /opt/ood/nginx_stage/share/nginx_stage_example.yml            /etc/ood/config/nginx_stage.yml
RUN cp /opt/ood/ood-portal-generator/share/ood_portal_example.yml    /etc/ood/config/ood_portal.yml

# make some misc directories & files
RUN mkdir -p /var/lib/ondemand-nginx/config/apps/{sys,dev,usr}
RUN touch /var/lib/ondemand-nginx/config/apps/sys/{dashboard,shell,myjobs}.conf

# setup sudoers for apache
RUN echo -e 'Defaults:apache !requiretty, !authenticate \n\
Defaults:apache env_keep += "NGINX_STAGE_* OOD_*" \n\
apache ALL=(ALL) NOPASSWD: /opt/ood/nginx_stage/sbin/nginx_stage' >/etc/sudoers.d/ood

# run the OOD executables to setup the env
RUN /opt/ood/ood-portal-generator/sbin/update_ood_portal --insecure
RUN /opt/ood/nginx_stage/sbin/update_nginx_stage
RUN echo $VERSION > /opt/ood/VERSION
# this one bc centos:8 doesn't generate localhost cert
RUN /usr/libexec/httpd-ssl-gencerts

EXPOSE 8080
EXPOSE 5556
EXPOSE 3035
CMD [ "/opt/ood/launch" ]
