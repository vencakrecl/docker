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

# Extensions install as root; the base image otherwise runs unprivileged as $SERVER_USER
# (www-data by default). gd links libpng (build + runtime), so install its dev package -
# named per distro via a detect-os case, the same pattern the image Dockerfiles use.
USER root
RUN case "$(helper detect-os)" in \
      alpine) runtime_deps="libpng-dev" ;; \
      debian) runtime_deps="libpng-dev" ;; \
    esac \
 && helper install-runtime-deps $runtime_deps \
 && helper install-docker-ext gd
USER ${SERVER_USER}
