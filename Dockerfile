# -------------------------------------------------------------------------
# Dockerfile to build the "fpm"" and "ssh" images
# -------------------------------------------------------------------------

ARG PHP_MINOR_VERSION=7.4
ARG NODE_VERSION=14
ARG PHP_PACKAGES=" \
    apcu \
    bcmath \
    bz2 \
    calendar \
    exif \
    gd \
    gettext \
    igbinary \
    imagick \
    intl \
    mcrypt \
    mysqli \
    opcache \
    pcntl \
    pdo_mysql \
    redis \
    shmop \
    soap \
    sockets \
    sysvmsg \
    sysvsem \
    sysvshm \
    uuid \
    xdebug \
    yaml \
    zip \
"

# -------------------------------------------------------------------------

FROM php:${PHP_MINOR_VERSION}-fpm as php-fpm

ARG PHP_MINOR_VERSION
ARG PHP_PACKAGES

RUN echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf.d/phpapp-norecommends && \
    echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/phpapp-suggests

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/bin/
RUN install-php-extensions $PHP_PACKAGES

# Other tools
RUN apt-get -qq update && apt-get -q install -y \
        # for TYPO3 \
        graphicsmagick \
        curl \
        # for causal/extractor: \
        exiftool poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# create an app user
RUN adduser --disabled-password --gecos "" application

# Disable XDEBUG by default (can be enabled via XDEBUG_MODE in entrypoint-extras.sh
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Add entrypoint scripts
COPY files/entrypoint*.sh /
RUN chmod +x /*.sh

# Configure PHP and PHP-FPM
ADD files/php.ini /usr/local/etc/php/conf.d/zz-custom.ini
ADD files/php-fpm-www.conf /usr/local/etc/php-fpm.d/www.conf

ENTRYPOINT [ "/entrypoint.sh" ]
# Override CMD too (see https://github.com/moby/moby/issues/5147)
CMD [ "php-fpm" ]

# -------------------------------------------------------------------------

FROM php-fpm as ssh

ARG NODE_VERSION
ARG PHP_MINOR_VERSION

RUN apt-get -qq update && apt-get -q install -y \
        # ssh daemon (use "PAM" to allow users to login without password)
        openssh-server sudo \
        # for composer:
        git zip make \
        # other tools for CLI pleasure:
        awscli groff \
        bash \
        bash-completion \
        default-mysql-client \
        iputils-ping \
        less \
        vim \
        wget \
        joe \
        jq \
        rsync \
        patch \
        screen \
        # for causal/extractor: \
        exiftool poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Configure ssh daemon
RUN set -ex \
    && rm -rf /etc/ssh/ssh_host_*_key \
    && ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key \
    # required to allow user without a password (else it is "locked"):
    && echo "UsePAM yes" >> /etc/ssh/sshd_config \
    && echo "application ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install node (pin, so that in doubt, the debian version is never installed)
RUN (echo "Package: *" && echo "Pin: origin deb.nodesource.com" && echo "Pin-Priority: 1000") > /etc/apt/preferences.d/nodesource && \
    curl -sL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash - && \
    sudo apt-get -q install -y -V nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install yarn and bower for convenience
RUN npm install -g yarn bower

# Install latest release of clitools (ct)
RUN set -ex && \
    latest_url=$(curl -s https://api.github.com/repos/cron-eu/clitools/releases/latest | jq -r ".assets[].browser_download_url") && \
    test "${PHP_MINOR_VERSION}" = "7.0" && latest_url=https://github.com/kitzberger/clitools/releases/download/2.5.4/clitools.phar && \
    curl -Lo /usr/local/bin/ct $latest_url && \
    chmod 777 /usr/local/bin/ct

# Also root uses bash
RUN usermod -s /bin/bash root

# Install composer
RUN curl --silent --show-error https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer

RUN usermod -s /bin/bash application

COPY files/ssh/ /

# Disable XDEBUG by default (can be enabled via XDEBUG_MODE in entrypoint-extras.sh
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
COPY files/entrypoint-extras.sh /

RUN chmod +x /*.sh && chown -R application. /home/application

ENTRYPOINT ["/bin/bash", "-c", "/entrypoint.sh"]
