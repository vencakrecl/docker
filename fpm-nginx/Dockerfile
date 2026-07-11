# syntax=docker/dockerfile:1
# PHP-FPM behind nginx, supervised by s6-overlay (/init as PID 1).
# Secure by default: runs unprivileged as www-data on a high port (8080).
# BASE_IMAGE is a php:*-fpm (Debian) or php:*-fpm-alpine image, set by the Makefile.
ARG BASE_IMAGE=php:8.4-fpm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
RUN helper install-packages nginx \
 && helper install-s6-overlay

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

COPY fpm-nginx/nginx.conf /etc/nginx/nginx.conf
# s6 services: php-fpm + nginx.
COPY fpm-nginx/s6-rc.d /etc/s6-overlay/s6-rc.d

# Optionally remap www-data to the host user's uid/gid for local development
# (bind-mounted files then get the right owner on Linux hosts). Done before the
# chown below so it picks up the new id. Leave unset to keep the hardened default.
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then helper set-user-id www-data "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi

# Make the runtime dirs writable by www-data so the whole stack (s6-overlay
# included) can run unprivileged. nginx listens on 8080, php-fpm on 9000 - both
# non-privileged ports, so no root/caps needed. /var/log/nginx is the symlink
# target of /var/lib/nginx/logs (chown -R does not follow the symlink).
RUN chown -R www-data:www-data /run /var/lib/nginx /var/log/nginx /var/www/html

USER www-data
WORKDIR /var/www/html
EXPOSE 8080
ENTRYPOINT ["/init"]
