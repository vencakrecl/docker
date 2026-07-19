# syntax=docker/dockerfile:1
ARG BASE_IMAGE=docker:29-dind-rootless

###> BASE IMAGE & TOOLBOX
FROM ${BASE_IMAGE}

COPY common/bin/ /usr/local/bin/
# Hash-verified pip lockfile for the CLOUD=azure variant (unused by other variants).
COPY dind/azure-cli-requirements.txt /usr/local/etc/azure-cli-requirements.txt
###< BASE IMAGE & TOOLBOX

###> CLOUD CLI
# Optional cloud CLI, selected at build time: CLOUD=aws|gcloud|azure (empty = plain
# dind). Each is installed via the shared jarvis-* commands (Alpine only, matching the dind base);
# the daemon still runs rootless, so switch to root just for the install. gcloud uses
# the system musl python3, hence CLOUDSDK_PYTHON. Tag suffix: -aws / -gcloud / -azure.
ARG CLOUD=
ENV CLOUDSDK_PYTHON=/usr/bin/python3
USER root
RUN case "${CLOUD}" in \
        aws)    jarvis-install-aws-cli ;; \
        gcloud) jarvis-install-gcloud ;; \
        azure)  jarvis-install-azure-cli ;; \
        "")     : ;; \
        *)      echo "dind: unknown CLOUD='${CLOUD}' (want aws|gcloud|azure)" >&2; exit 1 ;; \
    esac
USER rootless
###< CLOUD CLI

###> HEALTH CHECK
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD DOCKER_HOST=unix:///run/user/1000/docker.sock docker version >/dev/null 2>&1
###< HEALTH CHECK
