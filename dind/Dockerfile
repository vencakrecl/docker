# syntax=docker/dockerfile:1
# FIRST CUT - the Alpine variant is a thin layer over the official docker:*-dind
# image. There is no upstream Debian dind, so the Debian variant installs the
# Docker Engine via get.docker.com. NOTE: get.docker.com is not pinned, so the
# Debian build is not fully reproducible yet - pin the Docker apt repo before
# publishing. Run this image with --privileged.
# BASE_IMAGE is docker:*-dind (Alpine) or debian:*-slim, set by the Makefile.
ARG BASE_IMAGE=docker:29-dind
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
RUN if ! command -v dockerd >/dev/null 2>&1; then \
        helper install-packages ca-certificates curl; \
        curl -fsSL https://get.docker.com | sh; \
    fi

COPY dind/entrypoint.sh /usr/local/bin/dind-entrypoint

EXPOSE 2375 2376
ENTRYPOINT ["dind-entrypoint"]
CMD []
