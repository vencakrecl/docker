# Docker images

[![CI](https://github.com/vencakrecl/docker/actions/workflows/ci.yml/badge.svg)](https://github.com/vencakrecl/docker/actions/workflows/ci.yml)

Collection of Docker images. Every image is multi-arch (`linux/amd64` + `linux/arm64`) and
ships in **Debian** and **Alpine** variants.

## Images

| Image         | Description               |
|---------------|---------------------------|
| `fpm-nginx`   | PHP-FPM behind nginx      |
| `fpm-apache`  | PHP-FPM with Apache       |
| `frankenphp`  | FrankenPHP                |
| `dind`        | Docker-in-Docker (rootless); optional `-aws` / `-gcloud` / `-azure` cloud-CLI variants |

**Secure by default:** the web images (`fpm-nginx`, `fpm-apache`, `frankenphp`)
run unprivileged as `www-data` and listen on port **8080** (a non-privileged
port, so no root or capabilities are needed). `dind` is built on the **rootless**
Docker-in-Docker image, so its daemon also runs as a non-root user (`rootless`,
uid 1000) - though the container itself still needs `--privileged`.

## Quick start

```sh
# Pull a published image (GHCR, or Docker Hub when configured)
docker pull ghcr.io/vencakrecl/fpm-nginx:8.4-alpine
docker pull docker.io/vencakrecl/fpm-nginx:8.4-alpine

# ...or build one locally
make fpm-nginx-alpine
```

## Documentation

- [Naming & tags](docs/tags.md) - GHCR registry, tag format, multi-arch manifests
- [Configuration](docs/configuration.md) - PHP (`php.ini` / php-fpm) and logging env knobs
- [Building & local development](docs/building.md) - Makefile, the `helper` toolbox, host-user matching, Docker Compose
- [Testing & CI](docs/testing.md) - dgoss, the GitHub Actions matrix, status

## License

[MIT](LICENSE)
