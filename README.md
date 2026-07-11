# Docker images

Collection of Docker images. Every image is multi-arch (`linux/amd64` + `linux/arm64`) and
ships in **Debian** and **Alpine** variants.

## Images

| Image         | Description               |
|---------------|---------------------------|
| `fpm-nginx`   | PHP-FPM behind nginx      |
| `fpm-apache`  | PHP-FPM with Apache       |
| `frankenphp`  | FrankenPHP                |
| `dind`        | Docker-in-Docker          |

## Naming

Registry / namespace is not decided yet, so images are referred to by name only
(e.g. `fpm-nginx`); a prefix like `ghcr.io/<owner>/` is added later.

### Tags

Tag format is `[<version>-]<os>`, where `<os>` is `debian` or `alpine`.

| Image                                   | Tag format              | Examples                                 |
|-----------------------------------------|-------------------------|------------------------------------------|
| `fpm-nginx`, `fpm-apache`, `frankenphp` | `<php-version>-<os>`    | `8.3-debian`, `8.3-alpine`, `8.4-debian` |
| `dind`                                  | `<docker-version>-<os>` | `27-debian`, `27-alpine`                 |

### Architecture

Architecture is **not** part of the tag. Each tag is a manifest list that serves both
`linux/amd64` and `linux/arm64`; Docker selects the correct variant on pull. Build with:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t <image>:<tag> .
```

See https://docs.docker.com/build/building/multi-platform/

## Layout

```
Makefile              # local build targets
common/helper         # shared build toolbox, used by all images
common/php.ini        # shared PHP config, copied into conf.d on PHP images
<image>/Dockerfile    # one Dockerfile per image; base image via BASE_IMAGE arg
<image>/goss.yaml     # runtime tests for the image (dgoss)
```

Every image has a single Dockerfile. The Debian/Alpine difference is handled at
build time: the Makefile passes the base image as the `BASE_IMAGE` build arg, and
`common/helper` abstracts the distro. The build context is the repo root so each
Dockerfile can `COPY common/helper`.

`common/helper` is invoked as `helper <command>`:

| Command | Purpose |
|---------|---------|
| `detect-arch` / `detect-os` | canonical arch (`amd64`/`arm64`) and distro (`debian`/`alpine`) |
| `install-packages <pkgs...>` | apt-get or apk, with cache cleanup |
| `install-s6-overlay` | s6-overlay init/process supervisor |
| `install-composer` | Composer (sha256-verified) |
| `install-pie` | PIE, the PHP extension installer |
| `install-castor` | Castor task runner (static binary) |
| `install-pie-ext <ext...>` / `install-pie-skip-enable-ext <ext...>` | install PHP extension(s) via PIE, with / without enabling |
| `install-pecl-ext <ext...>` / `install-pecl-skip-enable-ext <ext...>` | install PHP extension(s) via PECL, with / without enabling |
| `install-docker-ext <ext...>` / `install-docker-skip-enable-ext <ext...>` | install PHP extension(s) via `docker-php-ext-install`, with / without enabling |

Tool versions are pinned at the top of `common/helper` and overridable via env
build args, e.g. `--build-arg COMPOSER_VERSION=2.10.2`.

## PHP configuration

The PHP images (`fpm-nginx`, `fpm-apache`, `frankenphp`) copy `common/php.ini`
into `$PHP_INI_DIR/conf.d/zz-common.ini`. PHP expands `${...}` in ini files from
the environment at startup and supports a `${VAR:-default}` fallback, so settings
carry their default in the ini and are overridable at runtime without a rebuild:

```sh
docker run -e PHP_MEMORY=512M ...   # memory_limit = 512M (default 128M)
```

Add more env-driven settings by adding `key = ${ENV_VAR:-default}` lines to
`common/php.ini` - no Dockerfile change needed.

## Building locally

```sh
make build              # all images, both OS variants
make fpm-nginx          # one image, both variants
make fpm-nginx-alpine   # one image, one variant
make help               # list targets
```

Overridable variables: `PHP_VERSION` (default 8.4), `DOCKER_VERSION` (default 29,
dind), `REGISTRY` (tag prefix, empty = local), `PLATFORM` (empty = host arch).

Local `make` builds use `--load`, which is host-arch only. Multi-arch images are a
push-time concern (`--platform linux/amd64,linux/arm64`), not wired into the
Makefile yet.

## Testing

Tests run against a **running** container with
[dgoss](https://github.com/goss-org/goss/tree/master/extras/dgoss): each target
starts the image and checks the `<image>/goss.yaml` in that image's directory.

```sh
make test           # runtime-test every image (Alpine)
make test-fpm-nginx # one image
```

Requires `goss` + `dgoss` on `PATH` (on macOS also set `GOSS_PATH` to a Linux goss
binary). What each image checks:

| Image | goss checks |
|-------|-------------|
| `fpm-nginx` | php-fpm + nginx running; `memory_limit` == 128M; GET `/ping.php` → 404 (fastcgi chain up) |
| `fpm-apache` | php-fpm running; `memory_limit` == 128M; GET `/` → 403 (empty docroot) |
| `frankenphp` | `memory_limit` == 128M; GET `/` → 308 (Caddy http→https redirect) |
| `dind` | `dockerd` running; `docker version` reaches the daemon (run `--privileged`) |

Notes: HTTP is used instead of a raw port check because Apache binds IPv6 on
Alpine but IPv4 on Debian, and it also exercises the server end-to-end. Avoid
Go-template `{{ }}` syntax anywhere in a goss.yaml (comments included) - goss
renders the file as a template first.

## Status

Building and smoke-tested: `fpm-nginx`, `frankenphp`.

First cut, needs iteration:
- `fpm-apache` - verified on Debian; Alpine's different Apache layout is best-effort.
- `dind` - Alpine is a thin layer over the official `docker:*-dind`; there is no
  upstream Debian dind, so the Debian variant installs the engine via
  `get.docker.com` (not version-pinned, so not yet reproducible).
