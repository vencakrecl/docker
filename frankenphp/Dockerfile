# syntax=docker/dockerfile:1
# FrankenPHP. BASE_IMAGE is a dunglas/frankenphp:*-bookworm (Debian) or
# dunglas/frankenphp:*-alpine image, set by the Makefile.
# The base image already ships the Caddy/FrankenPHP entrypoint serving /app/public.
ARG BASE_IMAGE=dunglas/frankenphp:php8.4-bookworm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

# Secure by default: run unprivileged as www-data. SERVER_NAME=:8080 makes
# FrankenPHP/Caddy serve plain HTTP on a high port (no 443/auto-TLS, no root).
# Caddy writes to /config and /data (XDG dirs); /app is the docroot.
ENV SERVER_NAME=:8080
# Optionally remap www-data to the host user's uid/gid for local development
# (done before the chown so it picks up the new id). Unset = hardened default.
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then helper set-user-id www-data "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi
RUN chown -R www-data:www-data /app /config /data

USER www-data
WORKDIR /app
EXPOSE 8080
