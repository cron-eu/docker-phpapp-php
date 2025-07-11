# -------------------------------------------------------------------------
# Dockerfile to build the "fpm"" and "ssh" images
# -------------------------------------------------------------------------

ARG PHP_MINOR_VERSION=8.4
ARG NODE_VERSION=20

# -------------------------------------------------------------------------

FROM php:${PHP_MINOR_VERSION}-fpm AS php-fpm

ARG PHP_MINOR_VERSION

RUN echo 'APT::Install-Recommends "0";' >> /etc/apt/apt.conf.d/phpapp-norecommends && \
    echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/phpapp-suggests

RUN <<EOF
	if grep '^VERSION_ID="9"' /etc/os-release >/dev/null ; then
		# Some fixes for debian scratch
		# Distro now in "archive"
		echo deb http://archive.debian.org/debian stretch main > /etc/apt/sources.list && \
		echo deb http://archive.debian.org/debian-security stretch/updates main >> /etc/apt/sources.list
		# Letsencrypt certificate no longer valid
		mkdir -p /usr/share/ca-certificates/letsencrypt/ \
			&& cd /usr/share/ca-certificates/letsencrypt/ \
			&& curl -kfsSLO https://letsencrypt.org/certs/isrgrootx1.pem \
			&& perl -i.bak -pe 's/^(mozilla\/DST_Root_CA_X3.crt)/!$1/g' /etc/ca-certificates.conf \
			&& update-ca-certificates
	fi
EOF

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/bin/
RUN <<EOT bash
    set -ex
    PHP_EXTENSIONS=(
      "apcu"
      "bcmath"
      "bz2"
      "calendar"
      "exif"
      "ffi"
      "gd"
      "gettext"
      "imagick"
      "intl"
      "ldap"
      "mysqli"
      "opcache"
      "pcntl"
      "pdo_mysql"
      "redis"
      "shmop"
      "soap"
      "sockets"
      "sysvmsg"
      "sysvsem"
      "sysvshm"
      "uuid"
      "vips"
      "xdebug"
      "yaml"
      "zip"
    )
    case "$PHP_MINOR_VERSION" in
        "8.0"|"8.1"|"8.2"|"8.3")
          # Legacy deprecated extension, but we had it until 8.3:
          PHP_EXTENSIONS+=("mcrypt")
          ;;
        *)
          ;;
    esac
    install-php-extensions \${PHP_EXTENSIONS[@]}

    # Install igbinary last, so that redis and others don't get support for it compiled in
    install-php-extensions igbinary
EOT

# Other tools
RUN apt-get -qq update && apt-get -q install -y \
        # for php-fpm healthcheck \
        libfcgi-bin \
        # for TYPO3 / Neos \
        imagemagick \
        graphicsmagick \
        ghostscript \
        curl \
        locales-all \
        unzip \
        # for causal/extractor: \
        exiftool poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Install wkhtmltopdf (only on PHP 7.0)
RUN <<-EOF
    set -ex \
    # Only need this in the PHP 7.0 package for now
    test "${PHP_MINOR_VERSION}" != "7.0" && exit
    apt-get -qq update && apt-get -q install -y lsb-release xfonts-base xfonts-75dpi fontconfig xvfb
    CODENAME=$(lsb_release -c -s)
    VERSION=0.12.6-1
    test "$CODENAME" = "bullseye" && VERSION=0.12.6.1-2
    PLATFORM=arm64
    test $(uname -m) = "x86_64" && PLATFORM=amd64
    curl -fsSL -o wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/${VERSION}/wkhtmltox_${VERSION}.${CODENAME}_${PLATFORM}.deb
    dpkg -i wkhtmltox.deb
    ln -s /usr/local/bin/wkhtmltopdf /usr/bin && ln -s /usr/local/bin/wkhtmltoimage /usr/bin
    rm -rf wkhtmltox.deb /var/lib/apt/lists/*
EOF

# Enable PDF/PS processing by ImageMagick again (disabled in distributions)
RUN perl -i -ne 'print if ! /rights="none".*"(PDF|PS.?|EPS|XPS)"/' /etc/ImageMagick-*/policy.xml

# Other versions:
# https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_amd64.deb
# https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_arm64.deb
# https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.buster_amd64.deb
# https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.buster_arm64.deb
# https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.stretch_amd64.deb
# https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.stretch_arm64.deb

# Install php-fpm healthcheck
ADD https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck /usr/local/bin/php-fpm-healthcheck
RUN chmod +x /usr/local/bin/php-fpm-healthcheck

HEALTHCHECK --interval=5s --timeout=1s CMD php-fpm-healthcheck || exit 1

# create an app user
RUN adduser --disabled-password --gecos "" application

# Disable XDEBUG by default (can be enabled via XDEBUG_MODE in entrypoint-extras.sh
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Add entrypoint scripts
COPY files/entrypoint*.sh /
RUN chmod 755 /*.sh

# Configure PHP and PHP-FPM
ADD files/php.ini /usr/local/etc/php/conf.d/zz-01-custom.ini

ENTRYPOINT [ "/entrypoint.sh" ]
# Override CMD too (see https://github.com/moby/moby/issues/5147)
CMD [ "php-fpm" ]

# -------------------------------------------------------------------------

FROM php-fpm AS ssh

ARG NODE_VERSION
ARG PHP_MINOR_VERSION

# Do not install "recommends" or "suggests" packages, less garbage
RUN echo 'APT::Install-Recommends "0";' >> /etc/apt/apt.conf.d/phpapp-norecommends && \
    echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/phpapp-suggests

# Install all tools we need in our standard PHP cli
RUN apt-get -qq update && apt-get -q install -y \
        # ssh daemon (use "PAM" to allow users to login without password)
        openssh-server sudo gosu \
        # for TYPO3 / Neos \
        imagemagick \
        graphicsmagick \
        ghostscript \
        curl \
        locales-all \
        unzip \
        # for causal/extractor: \
        exiftool poppler-utils \
        # for composer:
        git zip make \
        # other tools for CLI pleasure:
        awscli groff \
        bash \
        bash-completion \
        default-mysql-client \
        figlet \
        iputils-ping \
        less \
        vim \
        wget \
        joe \
        jq \
        redis-tools \
        rsync \
        patch \
        screen \
        # for causal/extractor: \
        exiftool poppler-utils \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc \
    && rm -f /usr/bin/redis-benchmark /usr/bin/redis-check-aof /usr/bin/redis-check-rdb

# Configure ssh daemon
RUN set -ex \
    && rm -rf /etc/ssh/ssh_host_*_key \
    && ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key \
    # required to allow user without a password (else it is "locked"):
    && echo "UsePAM yes" >> /etc/ssh/sshd_config \
    && echo "application ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install node (pin, so that in doubt, the debian version is never installed)
RUN (echo "Package: *" && echo "Pin: origin deb.nodesource.com" && echo "Pin-Priority: 1000") > /etc/apt/preferences.d/nodesource && \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash - && \
    sudo apt-get -q install -y -V nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install yarn and bower for convenience
RUN npm install -g yarn bower

# Install latest release of clitools (ct)
RUN <<-EOF
    set -ex
    latest_url=https://github.com/cron-eu/clitools/releases/download/2.8.0/clitools.phar
    test "${PHP_MINOR_VERSION}" = "7.0" && latest_url=https://github.com/kitzberger/clitools/releases/download/2.5.4/clitools.phar
    curl -fsSLo /usr/local/bin/ct $latest_url
    chmod 777 /usr/local/bin/ct
EOF

# Also root uses bash
RUN usermod -s /bin/bash root

# No Debian motd, we have our own "login information" in application's user .bash_profile
RUN rm -f /etc/motd

# Install composer
RUN curl -fsSL https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer

# Enable HEALTHCHECK for SSH container
HEALTHCHECK --interval=5s --timeout=1s CMD pgrep sshd > /dev/null || exit 1

RUN usermod -s /bin/bash application

COPY files/ssh/ /
COPY files/entrypoint-extras.sh /
# Fix permissions of copied files
RUN <<-EOF
    set -ex
    chmod 755 /etc /etc/profile.d /etc/profile.d/docker-prompt.sh
    find /home -type d -exec chmod 755 {} \;
    find /home -type f -exec chmod 644 {} \;
    chmod 755 /*.sh
EOF

# Disable XDEBUG by default (can be enabled via XDEBUG_MODE in entrypoint-extras.sh
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

RUN chmod +x /*.sh && chown -R application: /home/application

ENTRYPOINT ["/entrypoint.sh"]
