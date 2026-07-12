# syntax=docker/dockerfile:1
ARG BASE_IMAGE=docker:29-dind-rootless

###> BASE IMAGE & TOOLBOX
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
###< BASE IMAGE & TOOLBOX

###> HEALTH CHECK
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD DOCKER_HOST=unix:///run/user/1000/docker.sock docker version >/dev/null 2>&1
###< HEALTH CHECK
