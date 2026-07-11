#!/bin/sh
# Start the Docker daemon regardless of base image:
# the Alpine docker:*-dind base ships dockerd-entrypoint.sh (TLS cert handling,
# etc.); the Debian base only has a plain dockerd installed by the Dockerfile.
set -e
if command -v dockerd-entrypoint.sh >/dev/null 2>&1; then
    exec dockerd-entrypoint.sh "$@"
fi
exec dockerd "$@"
