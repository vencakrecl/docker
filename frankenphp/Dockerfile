# syntax=docker/dockerfile:1
# FrankenPHP. BASE_IMAGE is a dunglas/frankenphp:*-bookworm (Debian) or
# dunglas/frankenphp:*-alpine image, set by the Makefile.
# The base image already ships the Caddy/FrankenPHP entrypoint serving /app/public.
ARG BASE_IMAGE=dunglas/frankenphp:php8.5-bookworm
FROM ${BASE_IMAGE} AS base

COPY common/helper /usr/local/bin/helper
# Container health probe (HTTP GET $HEALTHCHECK_PATH, expects 2xx); see HEALTHCHECK.
COPY common/healthcheck /usr/local/bin/healthcheck

# Default PHP extension set - two per install manager (docker-php-ext, PECL, PIE), all
# needing no extra system libs. Installed explicitly with `helper`: the pecl/pie build
# toolchain ($PHPIZE_DEPS + unzip, an image ENV + a package) goes in as a removable group
# and is dropped afterwards. To *extend* this set, derive from this image and call
# `helper` in your own Dockerfile (see examples/wordpress) - no build-args, no repo context.
RUN helper install-build-deps $PHPIZE_DEPS unzip \
 && helper install-docker-ext mysqli bcmath \
 && helper install-pecl-ext redis-6.3.0 apcu-5.1.28 \
 && helper install-pie-ext php-ds/ext-ds:2.0.0 open-telemetry/ext-opentelemetry:1.3.1 \
 && helper remove-build-deps

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini ${PHP_INI_DIR}/conf.d/zz-common.ini

# Secure by default: run unprivileged as www-data. SERVER_NAME=:8080 makes
# FrankenPHP/Caddy serve plain HTTP on a high port (no 443/auto-TLS, no root).
# Caddy writes to /config and /data (XDG dirs). SERVER_ROOT is the docroot; the
# base Caddyfile reads it (root {$SERVER_ROOT:public/}), so it is overridable at
# runtime (docker run -e SERVER_ROOT=...).
ENV SERVER_NAME=:8080
ENV SERVER_ROOT=/app/public
# Request time budget (seconds). frankenphp has no FastCGI proxy, but the shared
# php.ini ties PHP's max_execution_time to it, so it caps request duration here too.
ENV SERVER_TIMEOUT=30
# Health endpoint (default HEALTHCHECK_PATH): frankenphp has no php-fpm to ping, so
# Caddy answers /healthz with a static 200 (no PHP runs) - the frankenphp equivalent of
# the fpm images' FPM ping. Injected via the base Caddyfile's
# {$CADDY_SERVER_EXTRA_DIRECTIVES} placeholder (inside the site block, before php_server).
# Overriding this env drops the route - re-add "respond /healthz 200" if you set your own.
ENV CADDY_SERVER_EXTRA_DIRECTIVES="respond /healthz 200"

# Hello-world landing page in the docroot, also the HEALTHCHECK target (index.php
# overrides the base welcome page); must come after ENV SERVER_ROOT and before the
# chown below so it is owned correctly.
COPY common/index.php ${SERVER_ROOT}/index.php
# HTTP path the HEALTHCHECK probes. Default /healthz is Caddy's static-200 health route
# (see CADDY_SERVER_EXTRA_DIRECTIVES above) - a cheap, app-independent liveness check.
# Set to / for an end-to-end check that serves index.php, or your app's route (e.g. /up).
ENV HEALTHCHECK_PATH=/healthz

# Server user (baked at build time). Unlike SERVER_ROOT this is not a runtime knob:
# USER and the chown below are fixed at build and the container runs non-root, so it
# cannot switch users at runtime. Override with --build-arg SERVER_USER=... to rebuild
# (or docker run --user at runtime).
ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

# Optionally remap $SERVER_USER to the host user's uid/gid for local development
# (done before the chown so it picks up the new id). Unset = hardened default.
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then helper set-user-id "$SERVER_USER" "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi
RUN chown -R "$SERVER_USER:$SERVER_USER" /app /config /data

USER ${SERVER_USER}
WORKDIR /app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["healthcheck"]

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
