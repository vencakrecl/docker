# syntax=docker/dockerfile:1
# FIRST CUT - verified on Debian; Alpine wiring is best-effort.
# PHP-FPM behind Apache (mod_proxy_fcgi), supervised by s6-overlay (/init as PID 1).
# Debian and Alpine lay Apache out very differently (config tree, module loading,
# control binary), so the build branches on the detected distro below.
# BASE_IMAGE is a php:*-fpm (Debian) or php:*-fpm-alpine image, set by the Makefile.
ARG BASE_IMAGE=php:8.5-fpm
FROM ${BASE_IMAGE} AS base

COPY common/helper /usr/local/bin/helper
# Container health probe (HTTP GET $HEALTHCHECK_PATH, expects 2xx); see HEALTHCHECK.
COPY common/healthcheck /usr/local/bin/healthcheck
# apache2 + mod_proxy_fcgi. On Alpine mod_proxy ships in a separate apache2-proxy
# package (Debian bundles it with apache2, enabled below via a2enmod); installing it
# lets Apache proxy .php to php-fpm (so .php executes, not served as source) and back
# the /healthz FPM-ping endpoint. apache2-proxy's conf.d/proxy.conf auto-loads the
# modules; no LoadModule edit needed on Alpine.
RUN helper install-runtime-deps apache2 \
 && if command -v apk >/dev/null 2>&1; then helper install-runtime-deps apache2-proxy; fi \
 && helper install-s6-overlay

# Default PHP extension set - two per install manager (docker-php-ext, PECL, PIE), all
# needing no extra system libs. Installed explicitly with `helper`: the pecl/pie build
# toolchain ($PHPIZE_DEPS + unzip, an image ENV + a package) goes in as a removable group
# and is dropped afterwards. To *extend* this set, derive from this image and call
# `helper` in your own Dockerfile (see examples/wordpress) - no build-args, no repo context.
RUN case "$(helper detect-os)" in \
      alpine) build_deps="$PHPIZE_DEPS unzip" ;; \
      debian) build_deps="$PHPIZE_DEPS unzip" ;; \
    esac \
 && helper install-build-deps $build_deps \
 && helper install-docker-ext mysqli bcmath \
 && helper install-pecl-ext redis-6.3.0 apcu-5.1.28 \
 && helper install-pie-ext php-ds/ext-ds:2.0.0 open-telemetry/ext-opentelemetry:1.3.1 \
 && helper remove-build-deps

# Document root, overridable at runtime; httpd expands ${SERVER_ROOT} in vhost.conf.
ENV SERVER_ROOT=/var/www/html
# Backend request timeout (seconds); httpd expands ${SERVER_TIMEOUT} in vhost.conf's
# ProxyTimeout so Apache doesn't 504 before PHP finishes. Overridable at runtime; raise
# it for long requests (PHP's own max_execution_time is an app/framework concern).
ENV SERVER_TIMEOUT=30

# Server user (baked at build time). Unlike SERVER_ROOT this is not a runtime knob:
# USER and the chown below are fixed at build and the container runs non-root, so it
# cannot switch users at runtime. Override with --build-arg SERVER_USER=... to rebuild
# (or docker run --user at runtime). httpd expands ${SERVER_USER} in the Alpine
# User/Group directives below (inert while non-root, but kept consistent).
ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini ${PHP_INI_DIR}/conf.d/zz-common.ini
# Shared PHP-FPM pool tuning (PHP_FPM_* env, defaults in the file).
COPY common/php-fpm.conf /usr/local/etc/php-fpm.d/zzz-common.conf

COPY fpm-apache/vhost.conf /etc/apache2/fpm-vhost.conf
# s6 services: php-fpm + apache.
COPY fpm-apache/s6-rc.d /etc/s6-overlay/s6-rc.d

# Enable the proxy_fcgi stack, include our vhost, and switch Apache to listen on
# 8080 as www-data (unprivileged), in whichever layout the base distro uses.
RUN set -eux; \
    if command -v a2enmod >/dev/null 2>&1; then \
        a2enmod proxy proxy_fcgi rewrite setenvif; \
        a2dissite 000-default 2>/dev/null || true; \
        sed -ri 's,^Listen 80$,Listen 8080,' /etc/apache2/ports.conf; \
        echo "IncludeOptional /etc/apache2/fpm-vhost.conf" >> /etc/apache2/apache2.conf; \
    else \
        sed -ri \
            -e 's,^#(LoadModule proxy_module .*),\1,' \
            -e 's,^#(LoadModule proxy_fcgi_module .*),\1,' \
            -e 's,^#(LoadModule rewrite_module .*),\1,' \
            -e 's,^#(LoadModule setenvif_module .*),\1,' \
            -e 's,^Listen 80$,Listen 8080,' \
            -e 's,^User apache$,User ${SERVER_USER},' \
            -e 's,^Group apache$,Group ${SERVER_USER},' \
            /etc/apache2/httpd.conf; \
        echo "Include /etc/apache2/fpm-vhost.conf" >> /etc/apache2/httpd.conf; \
    fi

# Optionally remap www-data to the host user's uid/gid for local development
# (done before the chown so it picks up the new id). Unset = hardened default.
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then helper set-user-id "$SERVER_USER" "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi

# Hello-world landing page in the docroot, also the HEALTHCHECK target. Debian's
# apache2 ships a default index.html; drop it so our index.php is the served
# DirectoryIndex (Alpine ships none - harmless). SERVER_ROOT is fixed at build time.
RUN rm -f ${SERVER_ROOT}/index.html
COPY common/index.php ${SERVER_ROOT}/index.php
# HTTP path the HEALTHCHECK probes. Default /healthz is php-fpm's ping endpoint (see
# common/php-fpm.conf + the vhost ProxyPass) - a cheap, app-independent liveness check.
# Set to / for an end-to-end check that serves index.php, or your app's route (e.g. /up).
ENV HEALTHCHECK_PATH=/healthz

# Secure by default: run unprivileged as $SERVER_USER. Make Apache's runtime and log
# dirs writable by it (port 8080 needs no privilege).
RUN chown -R "$SERVER_USER:$SERVER_USER" /run /var/log/apache2 /var/www/html 2>/dev/null || true

USER ${SERVER_USER}
WORKDIR /var/www/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["healthcheck"]
# The php:*-fpm base sets STOPSIGNAL SIGQUIT (php-fpm's own graceful signal), but here
# s6-overlay is PID 1 and only its SIGTERM handler triggers shutdown (its SIGQUIT
# handler is empty). Override so `docker stop` actually stops s6 gracefully instead of
# being SIGKILLed at the timeout. Per-service `down-signal SIGQUIT` then drains php-fpm
# and apache (finish in-flight requests) rather than hard-killing them.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]

# --- dev variant (build with --target dev; tag <php>-<os>-dev) ------------------------
# Layers the dev toolbox onto the lean image: composer + castor (binaries) and the
# xdebug/pcov/spx extensions (via PIE). xdebug is installed but off by default
# (XDEBUG_MODE) - see common/dev.ini.
FROM base AS dev
USER root
COPY common/dev.ini ${PHP_INI_DIR}/conf.d/zz-dev.ini
# The dev extensions' compile headers differ per distro (xdebug -> linux-headers on
# Alpine; spx -> zlib), so pick the build-deps list per system. unzip is also installed
# as a *kept* runtime package, so `composer install` can extract packages at runtime.
RUN helper install-composer \
 && helper install-castor \
 && case "$(helper detect-os)" in \
      alpine) build_deps="$PHPIZE_DEPS unzip linux-headers zlib-dev" runtime_deps="unzip" ;; \
      debian) build_deps="$PHPIZE_DEPS unzip zlib1g-dev" runtime_deps="unzip" ;; \
    esac \
 && helper install-runtime-deps $runtime_deps \
 && helper install-build-deps $build_deps \
 && helper install-pie-ext xdebug/xdebug:3.5.3 pecl/pcov:1.0.12 noisebynorthwest/php-spx:0.4.22 \
 && helper remove-build-deps
USER ${SERVER_USER}

# --- default (prod) stage: identical to `base`, kept last so a plain `docker build`
# with no --target (e.g. the examples' compose) still yields the lean image. ----------
FROM base AS prod
