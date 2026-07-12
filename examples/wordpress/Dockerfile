# WordPress on fpm-nginx, built by DERIVING from the fpm-nginx image.
#
# This is the intended way to add PHP extensions when you use these images as a base:
# the `helper` toolbox is baked into the image, so a downstream Dockerfile just calls it
# - no repo build context, no build-args, no rebuilding the base from source. WordPress
# needs mysqli (DB) + gd (images) beyond the stock extension set; gd links libpng at
# build and runtime, so libpng-dev is installed too (kept - it pulls the runtime lib).
#
# Build the base first: `make fpm-nginx-alpine` (from the repo root).
ARG BASE_IMAGE=fpm-nginx:8.4-alpine
FROM ${BASE_IMAGE}

# Extensions install as root; the base image otherwise runs unprivileged as www-data.
USER root
RUN helper install-packages libpng-dev \
 && helper install-docker-ext mysqli gd
USER www-data
