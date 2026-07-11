# syntax=docker/dockerfile:1
# Rootless Docker-in-Docker: the Docker daemon runs as the unprivileged "rootless"
# user (uid 1000) via rootlesskit. Still run the container with --privileged.
# BASE_IMAGE is docker:*-dind-rootless - Alpine only; there is no Debian/rootless
# upstream image, so dind is a single (rootless) variant. The base image's
# entrypoint (dockerd-entrypoint.sh), CMD, USER and EXPOSE are inherited.
ARG BASE_IMAGE=docker:29-dind-rootless
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper
