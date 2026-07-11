# syntax=docker/dockerfile:1
# FrankenPHP. BASE_IMAGE is a dunglas/frankenphp:*-bookworm (Debian) or
# dunglas/frankenphp:*-alpine image, set by the Makefile.
# The base image already ships the Caddy/FrankenPHP entrypoint serving /app/public.
ARG BASE_IMAGE=dunglas/frankenphp:php8.5-bookworm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
# Container health probe (HTTP GET $HEALTHCHECK_PATH, expects 2xx); see HEALTHCHECK.
COPY common/healthcheck /usr/local/bin/healthcheck

# Optionally build extra PHP extensions at build time. All optional, space-separated:
#   PHP_EXTENSIONS          docker-php-ext-install names (bundled), e.g. "mysqli gd"
#   PHP_PECL_EXTENSIONS     PECL packages, e.g. "redis apcu"
#   PHP_PIE_EXTENSIONS      PIE packages (composer vendor/name)
#   PHP_EXTENSION_PACKAGES  extra system libs some extensions need (e.g. "libpng-dev"),
#                           kept in the image (they may be needed at runtime)
# e.g. --build-arg PHP_EXTENSIONS="mysqli gd" --build-arg PHP_EXTENSION_PACKAGES="libpng-dev"
# pecl/pie compile from source, so the toolchain ($PHPIZE_DEPS, +unzip for pie) is added
# as a removable group and dropped afterwards to keep the image lean.
ARG PHP_EXTENSION_PACKAGES=""
ARG PHP_EXTENSIONS=""
ARG PHP_PECL_EXTENSIONS=""
ARG PHP_PIE_EXTENSIONS=""
RUN set -eu; \
    if [ -n "$PHP_EXTENSION_PACKAGES" ]; then helper install-packages $PHP_EXTENSION_PACKAGES; fi; \
    if [ -n "$PHP_EXTENSIONS" ]; then helper install-docker-ext $PHP_EXTENSIONS; fi; \
    if [ -n "$PHP_PECL_EXTENSIONS" ] || [ -n "$PHP_PIE_EXTENSIONS" ]; then \
      if [ -n "$PHP_PIE_EXTENSIONS" ]; then helper install-build-deps unzip; else helper install-build-deps; fi; \
      if [ -n "$PHP_PECL_EXTENSIONS" ]; then helper install-pecl-ext $PHP_PECL_EXTENSIONS; fi; \
      if [ -n "$PHP_PIE_EXTENSIONS" ]; then helper install-pie && helper install-pie-ext $PHP_PIE_EXTENSIONS; fi; \
      helper remove-build-deps; \
    fi

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

# Secure by default: run unprivileged as www-data. SERVER_NAME=:8080 makes
# FrankenPHP/Caddy serve plain HTTP on a high port (no 443/auto-TLS, no root).
# Caddy writes to /config and /data (XDG dirs). SERVER_ROOT is the docroot; the
# base Caddyfile reads it (root {$SERVER_ROOT:public/}), so it is overridable at
# runtime (docker run -e SERVER_ROOT=...).
ENV SERVER_NAME=:8080
ENV SERVER_ROOT=/app/public

# Hello-world landing page in the docroot, also the HEALTHCHECK target (index.php
# overrides the base welcome page); must come after ENV SERVER_ROOT and before the
# chown below so it is owned correctly.
COPY common/index.php ${SERVER_ROOT}/index.php
# HTTP path the HEALTHCHECK probes; / serves index.php (repoint at your app's health
# route if desired).
ENV HEALTHCHECK_PATH=/

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
