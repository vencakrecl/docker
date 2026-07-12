# syntax=docker/dockerfile:1
# PHP-FPM behind nginx, supervised by s6-overlay (/init as PID 1).
# Secure by default: runs unprivileged as www-data on a high port (8080).
# BASE_IMAGE is a php:*-fpm (Debian) or php:*-fpm-alpine image, set by the Makefile.
ARG BASE_IMAGE=php:8.5-fpm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
# Container health probe (HTTP GET $HEALTHCHECK_PATH, expects 2xx); see HEALTHCHECK.
COPY common/healthcheck /usr/local/bin/healthcheck
RUN helper install-packages nginx \
 && helper install-s6-overlay

# Optionally build extra PHP extensions at build time (all optional, space-separated):
#   PHP_EXTENSIONS          docker-php-ext-install names (bundled), e.g. "mysqli gd"
#   PHP_PECL_EXTENSIONS     PECL packages, e.g. "redis"
#   PHP_PIE_EXTENSIONS      PIE packages (composer vendor/name), e.g. "xdebug/xdebug"
#   PHP_EXTENSION_PACKAGES  extra system libs some extensions need (e.g. "libpng-dev"), kept
# helper install-extensions reads these and adds/removes the pecl/pie build deps itself.
ARG PHP_EXTENSION_PACKAGES=""
ARG PHP_EXTENSIONS=""
ARG PHP_PECL_EXTENSIONS=""
ARG PHP_PIE_EXTENSIONS=""
RUN helper install-extensions

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini
# Shared PHP-FPM pool tuning (PHP_FPM_* env, defaults in the file).
COPY common/php-fpm.conf /usr/local/etc/php-fpm.d/zzz-common.conf

# Document root, overridable at runtime. nginx cannot expand env vars, so the
# config ships as a template and the nginx s6 run script renders ${SERVER_ROOT}
# into /run/nginx.conf at container start.
ENV SERVER_ROOT=/var/www/html
# Backend request timeout (seconds), rendered into nginx's fastcgi_read_timeout so nginx
# doesn't 504 before PHP finishes. Overridable at runtime; raise it for long requests
# (PHP's own max_execution_time is an app/framework concern).
ENV SERVER_TIMEOUT=30
COPY fpm-nginx/nginx.conf /etc/nginx/nginx.conf.template
# s6 services: php-fpm + nginx.
COPY fpm-nginx/s6-rc.d /etc/s6-overlay/s6-rc.d

# Hello-world landing page in the docroot, also the HEALTHCHECK target (SERVER_ROOT
# is fixed to its default here at build time; mount your own docroot to override).
COPY common/index.php ${SERVER_ROOT}/index.php
# HTTP path the HEALTHCHECK probes. Default /healthz is php-fpm's ping endpoint (see
# common/php-fpm.conf + the nginx location) - a cheap, app-independent liveness check.
# Set to / for an end-to-end check that serves index.php, or your app's route (e.g. /up).
ENV HEALTHCHECK_PATH=/healthz

# Server user (baked at build time). Unlike SERVER_ROOT this is not a runtime knob:
# USER and the chown below are fixed at build and the container runs non-root, so it
# cannot switch users at runtime. Override with --build-arg SERVER_USER=... to rebuild
# (or docker run --user at runtime).
ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

# Optionally remap $SERVER_USER to the host user's uid/gid for local development
# (bind-mounted files then get the right owner on Linux hosts). Done before the
# chown below so it picks up the new id. Leave unset to keep the hardened default.
ARG USER_ID
ARG GROUP_ID
RUN if [ -n "$USER_ID" ]; then helper set-user-id "$SERVER_USER" "$USER_ID" "${GROUP_ID:-$USER_ID}"; fi

# Make the runtime dirs writable by $SERVER_USER so the whole stack (s6-overlay
# included) can run unprivileged. nginx listens on 8080, php-fpm on 9000 - both
# non-privileged ports, so no root/caps needed. /var/log/nginx is the symlink
# target of /var/lib/nginx/logs (chown -R does not follow the symlink).
RUN chown -R "$SERVER_USER:$SERVER_USER" /run /var/lib/nginx /var/log/nginx /var/www/html

USER ${SERVER_USER}
WORKDIR /var/www/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["healthcheck"]
# The php:*-fpm base sets STOPSIGNAL SIGQUIT (php-fpm's own graceful signal), but here
# s6-overlay is PID 1 and only its SIGTERM handler triggers shutdown (its SIGQUIT
# handler is empty). Override so `docker stop` actually stops s6 gracefully instead of
# being SIGKILLed at the timeout. Per-service `down-signal SIGQUIT` then drains php-fpm
# and nginx (finish in-flight requests) rather than hard-killing them.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]
