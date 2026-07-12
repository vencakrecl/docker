[← Back to README](../README.md)

# Naming & tags

CI publishes to **GHCR**: `ghcr.io/<owner>/<image>:<tag>` (e.g.
`ghcr.io/vencakrecl/fpm-nginx:8.4-alpine`). The registry prefix is the Makefile's
`REGISTRY` variable (empty for local builds).

## Tags

Tag format is `[<version>-]<os>`, where `<os>` is `debian` or `alpine`.

| Image                                   | Tag format              | Examples                                 |
|-----------------------------------------|-------------------------|------------------------------------------|
| `fpm-nginx`, `fpm-apache`, `frankenphp` | `<php-version>-<os>`    | `8.3-debian`, `8.3-alpine`, `8.4-debian` |
| web images, **dev variant**             | `<php-version>-<os>-dev` | `8.4-alpine-dev`, `8.4-debian-dev` (adds composer, castor, xdebug, pcov, spx) |
| `dind`                                  | `<docker-version>-rootless` | `29-rootless` (single variant; OS tag is meaningless here) |
| `dind`, **cloud variant**               | `<docker-version>-rootless-<cloud>` | `29-rootless-aws`, `29-rootless-gcloud`, `29-rootless-azure` (adds that cloud's CLI) |

## Architecture

Architecture is **not** part of the tag. Each tag is a manifest list that serves both
`linux/amd64` and `linux/arm64`; Docker selects the correct variant on pull. Build with:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t <image>:<tag> .
```

See https://docs.docker.com/build/building/multi-platform/
