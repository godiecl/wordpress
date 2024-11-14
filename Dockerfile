# time (docker buildx build --progress=plain --tag 4h/wordpress:latest --file Dockerfile .)
# https://hub.docker.com/_/wordpress/tags?name=6.6.2
ARG WORDPRESS_VERSION=6.6.2-php8.3-fpm-alpine

# https://www.php.net/supported-versions.php
ARG PHP_VERSION=8.3.13

# https://github.com/dunglas/frankenphp/releases
ARG FRANKENPHP_VERSION=1.3.0

ARG USER=www-data

# ---- FrankenPHP buider ----
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-builder-php${PHP_VERSION}-alpine AS builder

# copy xcaddy in the builder image
COPY --from=caddy:builder-alpine /usr/bin/xcaddy /usr/bin/xcaddy

# cgo must be enabled to build FrankenPHP
ENV CGO_ENABLED=1 XCADDY_SETCAP=1 XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath'

RUN xcaddy build \
    --output /usr/local/bin/frankenphp \
    --with github.com/dunglas/frankenphp=./ \
    --with github.com/dunglas/frankenphp/caddy=./caddy/ \
    --with github.com/dunglas/caddy-cbrotli

# ---- Wordpress ----
FROM wordpress:${WORDPRESS_VERSION} AS wp

# ---- FrankenPHP ----
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-alpine AS base

LABEL org.opencontainers.image.title="Wordpress with FrankenPHP"
LABEL org.opencontainers.image.description="Optimized WordPress containers to run everywhere. Built with FrankenPHP & Caddy."
LABEL org.opencontainers.image.url=https://4h.cl
LABEL org.opencontainers.image.source=https://github.com/godiecl/
LABEL org.opencontainers.image.vendor="Diego Urrutia-Astorga"

# replace the official binary by the one contained your custom modules
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# ENV WP_DEBUG=0
# ENV FORCE_HTTPS=0
ENV PHP_INI_SCAN_DIR=$PHP_INI_DIR/conf.d

# colorized bash
COPY .bashrc .dircolors /root/

# upgrade the base
RUN set -ex && \
    apk update --verbose && \
    apk upgrade --verbose && \
    apk add --no-cache --verbose \
        bash \
        ca-certificates \
        coreutils \
        curl \
        libcap \
        libeatmydata \
        nss-tools \
        sqlite \
        tzdata \
    && \
    cp /usr/share/zoneinfo/America/Santiago /etc/localtime && \
    echo "**** install docker-php-extension-installer ****" && \
    curl -sSLf -o /usr/local/bin/install-php-extensions https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions

# install extensions
RUN set -ex && \
    install-php-extensions imagick/imagick@master intl exif igbinary zip opcache timezonedb bcmath gd mysqli && \
    php -m && \
    php -v

# set recommended PHP.ini settings
RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY php.ini $PHP_INI_DIR/conf.d/wp.ini

# copy workdpress
COPY --from=wp /usr/src/wordpress /usr/src/wordpress
COPY --from=wp /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d/
COPY --from=wp /usr/local/bin/docker-entrypoint.sh /usr/local/bin/

# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
    { \
    echo 'opcache.enable=1'; \
    echo 'opcache.enable_cli=1'; \
    echo 'opcache.enable_file_override=1'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.interned_strings_buffer=32'; \
    echo 'opcache.jit_buffer_size=256M'; \
    echo 'opcache.max_accelerated_files=50000'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.optimization_level=0x7FFFBFFF'; \
    echo 'opcache.revalidate_freq=5'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.validate_timestamps=0'; \
    } > $PHP_INI_DIR/conf.d/opcache-recommended.ini

# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
    # https://www.php.net/manual/en/errorfunc.constants.php
    # https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
    echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'log_errors_max_len = 1024'; \
    echo 'ignore_repeated_errors = On'; \
    echo 'ignore_repeated_source = Off'; \
    echo 'html_errors = Off'; \
    } > $PHP_INI_DIR/conf.d/error-logging.ini

# install the SQLite plugin
COPY sqlite-database-integration.zip /usr/src/wordpress/sqlite-database-integration.zip
RUN unzip /usr/src/wordpress/sqlite-database-integration.zip -d /var/www/html/wp-content/mu-plugins/ && \
    rm /usr/src/wordpress/sqlite-database-integration.zip && \
    cp /var/www/html/wp-content/mu-plugins/sqlite-database-integration/db.copy /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/var\/www\/html\/wp-content\/mu-plugins\/sqlite-database-integration/g' /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /var/www/html/wp-content/db.php

WORKDIR /var/www/html

VOLUME /var/www/html/wp-content

RUN sed -i \
    -e 's/\[ "$1" = '\''php-fpm'\'' \]/\[\[ "$1" == frankenphp* \]\]/g' \
    -e 's/php-fpm/frankenphp/g' \
    /usr/local/bin/docker-entrypoint.sh

# add $_SERVER['ssl'] = true; when env USE_SSL = true is set to the wp-config.php file here: /usr/local/bin/wp-config-docker.php
# RUN sed -i 's/<?php/<?php if (!!getenv("FORCE_HTTPS")) { \$_SERVER["HTTPS"] = "on"; } define( "FS_METHOD", "direct" ); set_time_limit(300); /g' /usr/src/wordpress/wp-config-docker.php

# adding WordPress CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp

COPY Caddyfile /etc/caddy/Caddyfile

# format the Caddyfile
RUN frankenphp fmt --overwrite /etc/caddy/Caddyfile

# caddy requires an additional capability to bind to port 80 and 443
RUN setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp

# caddy requires write access to /data/caddy and /config/caddy
RUN chown -R ${USER}:${USER} /data/caddy && \
    chown -R ${USER}:${USER} /config/caddy && \
    chown -R ${USER}:${USER} /var/www/html && \
    chown -R ${USER}:${USER} /usr/src/wordpress && \
    chown -R ${USER}:${USER} /usr/local/bin/docker-entrypoint.sh

USER $USER

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
