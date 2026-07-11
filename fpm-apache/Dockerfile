# syntax=docker/dockerfile:1
# FIRST CUT - verified on Debian; Alpine wiring is best-effort.
# PHP-FPM behind Apache (mod_proxy_fcgi), supervised by s6-overlay (/init as PID 1).
# Debian and Alpine lay Apache out very differently (config tree, module loading,
# control binary), so the build branches on the detected distro below.
# BASE_IMAGE is a php:*-fpm (Debian) or php:*-fpm-alpine image, set by the Makefile.
ARG BASE_IMAGE=php:8.4-fpm
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
RUN helper install-packages apache2 \
 && helper install-s6-overlay

# Shared PHP config; memory_limit is driven by PHP_MEMORY (default in php.ini).
COPY common/php.ini /usr/local/etc/php/conf.d/zz-common.ini

COPY fpm-apache/vhost.conf /etc/apache2/fpm-vhost.conf
# s6 services: php-fpm + apache.
COPY fpm-apache/s6-rc.d /etc/s6-overlay/s6-rc.d

# Enable the proxy_fcgi stack and include our vhost, in whichever layout the
# base distro uses.
RUN set -eux; \
    if command -v a2enmod >/dev/null 2>&1; then \
        a2enmod proxy proxy_fcgi rewrite setenvif; \
        a2dissite 000-default 2>/dev/null || true; \
        echo "IncludeOptional /etc/apache2/fpm-vhost.conf" >> /etc/apache2/apache2.conf; \
    else \
        sed -ri \
            -e 's,^#(LoadModule proxy_module .*),\1,' \
            -e 's,^#(LoadModule proxy_fcgi_module .*),\1,' \
            -e 's,^#(LoadModule rewrite_module .*),\1,' \
            -e 's,^#(LoadModule setenvif_module .*),\1,' \
            /etc/apache2/httpd.conf; \
        echo "Include /etc/apache2/fpm-vhost.conf" >> /etc/apache2/httpd.conf; \
    fi

WORKDIR /var/www/html
EXPOSE 80
ENTRYPOINT ["/init"]
