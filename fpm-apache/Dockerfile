# syntax=docker/dockerfile:1
ARG BASE_IMAGE=php:8.5-fpm

###> BASE IMAGE
FROM ${BASE_IMAGE} AS base

###> RUNTIME DEPS
COPY common/bin/ /usr/local/bin/
COPY common/healthcheck /usr/local/bin/healthcheck
RUN jarvis-install-runtime-deps apache2 \
 && if [ "$(jarvis-detect-os)" = alpine ]; then jarvis-install-runtime-deps apache2-proxy apache2-brotli; fi \
 && jarvis-install-s6-overlay
###< RUNTIME DEPS

###> PHP EXTENSIONS
RUN set -f \
 && case "$(jarvis-detect-os)" in \
      alpine) \
        # Shared extension toolchain and source extraction.
        build_deps="$PHPIZE_DEPS unzip \
          # pdo_pgsql
          postgresql-dev \
          # intl
          icu-dev \
          # zip
          libzip-dev \
          # gd: FreeType, JPEG, PNG, WebP
          freetype-dev libjpeg-turbo-dev libpng-dev libwebp-dev \
          # imagick
          imagemagick-dev"; \
        runtime_deps=" \
          # pdo_pgsql
          libpq \
          # intl: libraries and full locale data
          icu-libs icu-data-full \
          # zip
          libzip \
          # gd: FreeType, JPEG, PNG, WebP
          freetype libjpeg-turbo libpng libwebp \
          # imagick: ImageMagick and JPEG/WebP coders
          imagemagick imagemagick-jpeg imagemagick-webp" ;; \
      debian) \
        # Shared extension toolchain and source extraction.
        build_deps="$PHPIZE_DEPS unzip \
          # pdo_pgsql
          libpq-dev \
          # intl
          libicu-dev \
          # zip
          libzip-dev \
          # gd: FreeType, JPEG, PNG, WebP
          libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
          # imagick
          libmagickwand-dev"; \
        runtime_deps=' \
          # pdo_pgsql
          libpq5 \
          # intl
          ~n^libicu[0-9]+$ \
          # zip
          ~n^libzip[0-9]+$ \
          # gd: FreeType, JPEG, WebP, PNG (including t64; exclude virtual packages)
          libfreetype6 libjpeg62-turbo libwebp7 \
          ?and(?not(?virtual),?name("^libpng[0-9]+-[0-9]+(t64)?$")) \
          # imagick
          imagemagick' ;; \
    esac \
 && jarvis-install-runtime-deps $runtime_deps \
 && jarvis-install-build-deps $build_deps \
 && jarvis-install-docker-ext \
      mysqli \
      pdo_mysql \
      pdo_pgsql \
      bcmath \
      intl \
      zip \
      "gd --with-freetype --with-jpeg --with-webp" \
      exif \
      pcntl \
 && jarvis-install-pie-ext \
      igbinary/igbinary:@RC \
      imagick/imagick \
      phpredis/phpredis \
      apcu/apcu \
 && jarvis-remove-build-deps
###< PHP EXTENSIONS

###> SERVER SETTINGS
ENV SERVER_ROOT=/var/www/html
ENV SERVER_TIMEOUT=30
ENV APACHE_LOG_LEVEL=warn

ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

COPY fpm-apache/vhost.conf /etc/apache2/fpm-vhost.conf
COPY fpm-apache/alpine.conf /etc/apache2/conf.d/zz-fpm.conf
COPY fpm-apache/debian.conf /etc/apache2/conf-enabled/zz-fpm.conf
COPY fpm-apache/ports.conf /etc/apache2/ports.conf
COPY fpm-apache/etc /etc

# Alpine Listen and CustomLog directives accumulate; disable the stock entries.
RUN set -eux; \
    case "$(jarvis-detect-os)" in \
      debian) \
        a2enmod proxy proxy_fcgi rewrite setenvif deflate brotli filter; \
        a2dissite 000-default 2>/dev/null || true; \
        a2disconf other-vhosts-access-log 2>/dev/null || true; \
        ;; \
      alpine) \
        sed -ri -e 's,^Listen 80$,#&,' -e 's,^[[:space:]]*CustomLog[[:space:]],#&,' /etc/apache2/httpd.conf; \
        ;; \
    esac

RUN rm -f ${SERVER_ROOT}/index.html
COPY common/index.php ${SERVER_ROOT}/index.php
ENV HEALTHCHECK_PATH=/healthz
###< SERVER SETTINGS

###> PHP & FPM CONFIGURATION
COPY common/php.ini ${PHP_INI_DIR}/conf.d/zz-common.ini
COPY common/php-fpm.conf /usr/local/etc/php-fpm.d/zzz-common.conf
###< PHP & FPM CONFIGURATION

###> NON-ROOT USER
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then jarvis-set-user-id "$SERVER_USER" "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi

RUN chown -R "$SERVER_USER:$SERVER_USER" /run /var/www/html 2>/dev/null || true

USER ${SERVER_USER}
###< NON-ROOT USER

###> ENTRYPOINT & RUNTIME METADATA
WORKDIR /var/www/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["healthcheck"]
# s6 needs SIGTERM to shut down; services use SIGQUIT to drain requests.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]
###< ENTRYPOINT & RUNTIME METADATA
###< BASE IMAGE

###> DEV IMAGE
FROM base AS dev
USER root

###> PHP EXTENSIONS
RUN jarvis-install-composer \
 && jarvis-install-castor \
 && case "$(jarvis-detect-os)" in \
      alpine) \
        # Shared dev extension toolchain and source extraction.
        build_deps="$PHPIZE_DEPS unzip libtool \
          # xdebug: Linux headers
          linux-headers \
          # php-spx: compression
          zlib-dev"; \
        runtime_deps=" \
          # Composer: ZIP archive extraction
          unzip" ;; \
      debian) \
        # Shared dev extension toolchain and source extraction.
        build_deps="$PHPIZE_DEPS unzip libtool \
          # php-spx: compression
          zlib1g-dev"; \
        runtime_deps=" \
          # Composer: ZIP archive extraction
          unzip" ;; \
    esac \
 && jarvis-install-runtime-deps $runtime_deps \
 && jarvis-install-build-deps $build_deps \
 && jarvis-install-pie-ext \
      xdebug/xdebug \
      pecl/pcov \
      noisebynorthwest/php-spx \
 && jarvis-remove-build-deps
###< PHP EXTENSIONS

###> PHP & FPM CONFIGURATION
COPY common/dev.ini ${PHP_INI_DIR}/conf.d/zz-dev.ini
###< PHP & FPM CONFIGURATION

USER ${SERVER_USER}
###< DEV IMAGE

###> PROD IMAGE
FROM base AS prod
###< PROD IMAGE
