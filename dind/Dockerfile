# syntax=docker/dockerfile:1
# Rootless Docker-in-Docker: the Docker daemon runs as the unprivileged "rootless"
# user (uid 1000) via rootlesskit. Still run the container with --privileged.
# BASE_IMAGE is docker:*-dind-rootless - Alpine only; there is no Debian/rootless
# upstream image, so dind is a single (rootless) variant. The base image's
# entrypoint (dockerd-entrypoint.sh), CMD, USER and EXPOSE are inherited.
ARG BASE_IMAGE=docker:29-dind-rootless
FROM ${BASE_IMAGE}

COPY common/helper /usr/local/bin/helper

# Healthy = the rootless daemon answers on its per-user socket. Longer start-period:
# rootlesskit + the daemon take a while to come up. Shell form so DOCKER_HOST is set
# for the client only (dockerd itself does not read it).
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD DOCKER_HOST=unix:///run/user/1000/docker.sock docker version >/dev/null 2>&1
