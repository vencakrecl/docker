# syntax=docker/dockerfile:1
ARG BASE_IMAGE=php:8.5-fpm

###> BASE IMAGE
FROM ${BASE_IMAGE} AS base

###> RUNTIME DEPS
COPY common/helper /usr/local/bin/helper
COPY common/healthcheck /usr/local/bin/healthcheck
RUN helper install-runtime-deps apache2 \
 && if [ "$(helper detect-os)" = alpine ]; then helper install-runtime-deps apache2-proxy apache2-brotli; fi \
 && helper install-s6-overlay
###< RUNTIME DEPS

###> PHP EXTENSIONS
RUN case "$(helper detect-os)" in \
      alpine) build_deps="$PHPIZE_DEPS unzip" ;; \
      debian) build_deps="$PHPIZE_DEPS unzip" ;; \
    esac \
 && helper install-build-deps $build_deps \
 && helper install-docker-ext mysqli bcmath \
 && helper install-pecl-ext redis-6.3.0 apcu-5.1.28 \
 && helper install-pie-ext php-ds/ext-ds:2.0.0 open-telemetry/ext-opentelemetry:1.3.1 \
 && helper remove-build-deps
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
COPY fpm-apache/s6-rc.d /etc/s6-overlay/s6-rc.d

# Debian: enable modules + drop stock sites (port/vhost come from the COPYed files above).
# Alpine: alpine.conf carries the config, but httpd.conf hardcodes `Listen 80` + a file
# `CustomLog` inline - both accumulate, so no include overrides them; comment them out.
RUN set -eux; \
    case "$(helper detect-os)" in \
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
RUN if [ -n "$USER_ID" ]; then helper set-user-id "$SERVER_USER" "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi

RUN chown -R "$SERVER_USER:$SERVER_USER" /run /var/www/html 2>/dev/null || true

USER ${SERVER_USER}
###< NON-ROOT USER

###> ENTRYPOINT & RUNTIME METADATA
WORKDIR /var/www/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["healthcheck"]
# s6 (PID 1) shuts down on SIGTERM, not the base's inherited SIGQUIT (else docker stop
# hangs to SIGKILL). Per-service down-signal SIGQUIT drains in-flight requests.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]
###< ENTRYPOINT & RUNTIME METADATA
###< BASE IMAGE

###> DEV IMAGE
FROM base AS dev
USER root

###> PHP EXTENSIONS
RUN helper install-composer \
 && helper install-castor \
 && case "$(helper detect-os)" in \
      alpine) build_deps="$PHPIZE_DEPS unzip libtool linux-headers zlib-dev" runtime_deps="unzip" ;; \
      debian) build_deps="$PHPIZE_DEPS unzip libtool zlib1g-dev" runtime_deps="unzip" ;; \
    esac \
 && helper install-runtime-deps $runtime_deps \
 && helper install-build-deps $build_deps \
 && helper install-pie-ext xdebug/xdebug:3.5.3 pecl/pcov:1.0.12 noisebynorthwest/php-spx:0.4.22 \
 && helper remove-build-deps
###< PHP EXTENSIONS

###> PHP & FPM CONFIGURATION
COPY common/dev.ini ${PHP_INI_DIR}/conf.d/zz-dev.ini
###< PHP & FPM CONFIGURATION

USER ${SERVER_USER}
###< DEV IMAGE

###> PROD IMAGE
FROM base AS prod
###< PROD IMAGE
