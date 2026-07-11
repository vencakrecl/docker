# syntax=docker/dockerfile:1
# PHP-FPM behind nginx, supervised by s6-overlay (/init as PID 1).
# BASE_IMAGE is a php:*-fpm (Debian) or php:*-fpm-alpine image, set by the Makefile.
ARG BASE_IMAGE=php:8.4-fpm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
RUN helper install-packages nginx \
 && helper install-s6-overlay

# Shared PHP config; memory_limit is driven by PHP_MEMORY (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

COPY fpm-nginx/nginx.conf /etc/nginx/nginx.conf
# s6 services: php-fpm + nginx.
COPY fpm-nginx/s6-rc.d /etc/s6-overlay/s6-rc.d

WORKDIR /var/www/html
EXPOSE 80
ENTRYPOINT ["/init"]
