# syntax=docker/dockerfile:1
ARG BASE_IMAGE=dunglas/frankenphp:php8.5-bookworm

###> BASE IMAGE
FROM ${BASE_IMAGE} AS base

###> RUNTIME DEPS
COPY common/bin/ /usr/local/bin/
COPY common/healthcheck /usr/local/bin/healthcheck
###< RUNTIME DEPS

###> PHP EXTENSIONS
RUN case "$(jarvis-detect-os)" in \
      alpine) build_deps="$PHPIZE_DEPS unzip" ;; \
      debian) build_deps="$PHPIZE_DEPS unzip" ;; \
    esac \
 && jarvis-install-build-deps $build_deps \
 && jarvis-install-docker-ext mysqli bcmath \
 && jarvis-install-pecl-ext redis-6.3.0 apcu-5.1.28 \
 && jarvis-install-pie-ext php-ds/ext-ds:2.0.0 open-telemetry/ext-opentelemetry:1.3.1 \
 && jarvis-remove-build-deps
###< PHP EXTENSIONS

###> SERVER SETTINGS
ENV SERVER_NAME=:8080
ENV SERVER_ROOT=/app/public
ENV SERVER_TIMEOUT=30

ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

# Our own Caddyfile (serves /healthz + php_server); the base CMD already points
# --config at this path. /healthz now lives in the Caddyfile, so CADDY_SERVER_EXTRA_DIRECTIVES
# is free again as a user escape hatch (empty default, see the Caddyfile).
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
      alpine) build_deps="$PHPIZE_DEPS unzip libtool linux-headers zlib-dev" runtime_deps="unzip" ;; \
      debian) build_deps="$PHPIZE_DEPS unzip libtool zlib1g-dev" runtime_deps="unzip" ;; \
    esac \
 && jarvis-install-runtime-deps $runtime_deps \
 && jarvis-install-build-deps $build_deps \
 && jarvis-install-pie-ext xdebug/xdebug:3.5.3 pecl/pcov:1.0.12 noisebynorthwest/php-spx:0.4.22 \
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
