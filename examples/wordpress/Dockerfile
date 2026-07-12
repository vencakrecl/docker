# WordPress on fpm-nginx, built by DERIVING from the fpm-nginx image.
#
# This is the intended way to EXTEND the image's default extensions when you use it as a
# base: the `helper` toolbox is baked into the image, so a downstream Dockerfile just
# calls it - no repo build context, no build-args, no rebuilding from source. The
# fpm-nginx image already ships mysqli (one of its defaults); WordPress needs one more,
# gd (images), which links libpng at build and runtime, so libpng-dev is installed too
# (kept - it pulls in the runtime lib).
#
# Build the base first: `make fpm-nginx-alpine` (from the repo root).
ARG BASE_IMAGE=fpm-nginx:8.4-alpine
FROM ${BASE_IMAGE}

# Extensions install as root; the base image otherwise runs unprivileged as www-data.
USER root
RUN helper install-runtime-deps libpng-dev \
 && helper install-docker-ext gd
USER www-data
