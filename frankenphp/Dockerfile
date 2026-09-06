# syntax=docker/dockerfile:1
ARG BASE_IMAGE=dunglas/frankenphp:php8.5-bookworm

###> BASE IMAGE
FROM ${BASE_IMAGE} AS base

###> RUNTIME DEPS
COPY common/bin/ /usr/local/bin/
COPY common/healthcheck /usr/local/bin/healthcheck
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
ENV SERVER_NAME=:8080
ENV SERVER_ROOT=/app/public
ENV SERVER_TIMEOUT=30

ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

COPY frankenphp/Caddyfile /etc/frankenphp/Caddyfile

COPY common/index.php ${SERVER_ROOT}/index.php
ENV HEALTHCHECK_PATH=/healthz
###< SERVER SETTINGS

###> PHP CONFIGURATION
COPY common/php.ini ${PHP_INI_DIR}/conf.d/zz-common.ini
###< PHP CONFIGURATION

###> NON-ROOT USER
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then jarvis-set-user-id "$SERVER_USER" "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi
RUN chown -R "$SERVER_USER:$SERVER_USER" /app /config /data

USER ${SERVER_USER}
###< NON-ROOT USER

###> ENTRYPOINT & RUNTIME METADATA
WORKDIR /app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["healthcheck"]
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

###> PHP CONFIGURATION
COPY common/dev.ini ${PHP_INI_DIR}/conf.d/zz-dev.ini
###< PHP CONFIGURATION

USER ${SERVER_USER}
###< DEV IMAGE

###> PROD IMAGE
FROM base AS prod
###< PROD IMAGE
