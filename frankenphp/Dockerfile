# syntax=docker/dockerfile:1
# FrankenPHP. BASE_IMAGE is a dunglas/frankenphp:*-bookworm (Debian) or
# dunglas/frankenphp:*-alpine image, set by the Makefile.
# The base image already ships the Caddy/FrankenPHP entrypoint serving /app/public.
ARG BASE_IMAGE=dunglas/frankenphp:php8.4-bookworm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

# Hello-world landing page (docroot is /app/public; overrides the base welcome page).
COPY common/index.php /app/public/index.php

# Secure by default: run unprivileged as www-data. SERVER_NAME=:8080 makes
# FrankenPHP/Caddy serve plain HTTP on a high port (no 443/auto-TLS, no root).
# Caddy writes to /config and /data (XDG dirs). SERVER_ROOT is the docroot; the
# base Caddyfile reads it (root {$SERVER_ROOT:public/}), so it is overridable at
# runtime (docker run -e SERVER_ROOT=...).
ENV SERVER_NAME=:8080
ENV SERVER_ROOT=/app/public
# Optionally remap www-data to the host user's uid/gid for local development
# (done before the chown so it picks up the new id). Unset = hardened default.
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then helper set-user-id www-data "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi
RUN chown -R www-data:www-data /app /config /data

USER www-data
WORKDIR /app
EXPOSE 8080
