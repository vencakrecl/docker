# syntax=docker/dockerfile:1
# FIRST CUT - verified on Debian; Alpine wiring is best-effort.
# PHP-FPM behind Apache (mod_proxy_fcgi), supervised by s6-overlay (/init as PID 1).
# Debian and Alpine lay Apache out very differently (config tree, module loading,
# control binary), so the build branches on the detected distro below.
# BASE_IMAGE is a php:*-fpm (Debian) or php:*-fpm-alpine image, set by the Makefile.
ARG BASE_IMAGE=php:8.5-fpm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
# Container health probe (HTTP GET $HEALTHCHECK_PATH, expects 2xx); see HEALTHCHECK.
COPY common/healthcheck /usr/local/bin/healthcheck
RUN helper install-packages apache2 \
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

# Document root, overridable at runtime; httpd expands ${SERVER_ROOT} in vhost.conf.
ENV SERVER_ROOT=/var/www/html
# Backend request timeout (seconds); httpd expands ${SERVER_TIMEOUT} in vhost.conf's
# ProxyTimeout so Apache doesn't 504 before PHP finishes. Overridable at runtime; raise
# it (and PHP's max_execution_time) together for long requests.
ENV SERVER_TIMEOUT=30

# Server user (baked at build time). Unlike SERVER_ROOT this is not a runtime knob:
# USER and the chown below are fixed at build and the container runs non-root, so it
# cannot switch users at runtime. Override with --build-arg SERVER_USER=... to rebuild
# (or docker run --user at runtime). httpd expands ${SERVER_USER} in the Alpine
# User/Group directives below (inert while non-root, but kept consistent).
ARG SERVER_USER=www-data
ENV SERVER_USER=${SERVER_USER}

# Shared PHP config; memory_limit is driven by PHP_MEMORY_LIMIT (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini
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
# HTTP path the HEALTHCHECK probes; / serves index.php (repoint at your app's health
# route if desired).
ENV HEALTHCHECK_PATH=/

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
