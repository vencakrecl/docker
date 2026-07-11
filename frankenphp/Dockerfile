# syntax=docker/dockerfile:1
# FrankenPHP. BASE_IMAGE is a dunglas/frankenphp:*-bookworm (Debian) or
# dunglas/frankenphp:*-alpine image, set by the Makefile.
# The base image already ships the Caddy/FrankenPHP entrypoint serving /app/public.
ARG BASE_IMAGE=dunglas/frankenphp:php8.4-bookworm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper

# Shared PHP config; memory_limit is driven by PHP_MEMORY (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

WORKDIR /app
