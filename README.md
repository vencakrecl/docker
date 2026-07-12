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
| `dind`        | Docker-in-Docker (rootless) |

**Secure by default:** the web images (`fpm-nginx`, `fpm-apache`, `frankenphp`)
run unprivileged as `www-data` and listen on port **8080** (a non-privileged
port, so no root or capabilities are needed). `dind` is built on the **rootless**
Docker-in-Docker image, so its daemon also runs as a non-root user (`rootless`,
uid 1000) - though the container itself still needs `--privileged`.

## Naming

CI publishes to **GHCR**: `ghcr.io/<owner>/<image>:<tag>` (e.g.
`ghcr.io/vencakrecl/fpm-nginx:8.4-alpine`). The registry prefix is the Makefile's
`REGISTRY` variable (empty for local builds).

### Tags

Tag format is `[<version>-]<os>`, where `<os>` is `debian` or `alpine`.

| Image                                   | Tag format              | Examples                                 |
|-----------------------------------------|-------------------------|------------------------------------------|
| `fpm-nginx`, `fpm-apache`, `frankenphp` | `<php-version>-<os>`    | `8.3-debian`, `8.3-alpine`, `8.4-debian` |
| web images, **dev variant**             | `<php-version>-<os>-dev` | `8.4-alpine-dev`, `8.4-debian-dev` (adds composer, castor, xdebug, pcov, spx) |
| `dind`                                  | `<docker-version>-rootless` | `29-rootless` (single variant; OS tag is meaningless here) |

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
common/php-fpm.conf   # shared PHP-FPM pool tuning, for the fpm images
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
| `set-user-id <user> <uid> [gid]` | change a user's uid/gid (host-user matching) |
| `install-runtime-deps <pkgs...>` | apt-get or apk, with cache cleanup |
| `install-s6-overlay` | s6-overlay init/process supervisor |
| `install-composer` | Composer (sha256-verified) |
| `install-pie` | PIE, the PHP extension installer |
| `install-castor` | Castor task runner (static binary) |
| `install-build-deps <pkgs...>` / `remove-build-deps` | install the pecl/pie toolchain as a removable group, then drop what was added |
| `install-pie-ext <ext...>` | install + enable PHP extension(s) via PIE |
| `install-pecl-ext <ext...>` | install + enable PHP extension(s) via PECL |
| `install-docker-ext <ext...>` | install + enable PHP extension(s) via `docker-php-ext-install` |

Tool versions are pinned at the top of `common/helper` (`S6_OVERLAY_VERSION`,
`COMPOSER_VERSION`, `PIE_VERSION`, `CASTOR_VERSION`). Edit them there to change a
version; they read from the environment, so a Dockerfile can also declare a matching
`ARG` and pass it through if you want per-build overrides.

## PHP configuration

The PHP images (`fpm-nginx`, `fpm-apache`, `frankenphp`) copy `common/php.ini`
into `$PHP_INI_DIR/conf.d/zz-common.ini`. PHP expands `${...}` in ini files from
the environment at startup and supports a `${VAR:-default}` fallback, so settings
carry their default in the ini and are overridable at runtime without a rebuild:

```sh
docker run -e PHP_MEMORY_LIMIT=512M ...   # memory_limit = 512M (default 128M)
```

Add more env-driven settings by adding `key = ${ENV_VAR:-default}` lines to
`common/php.ini` - no Dockerfile change needed.

The fpm images (`fpm-nginx`, `fpm-apache`) also copy `common/php-fpm.conf` into
`/usr/local/etc/php-fpm.d/zzz-common.conf` for process-manager tuning. php-fpm
supports the same `${VAR:-default}` expansion, so the pool is tunable at runtime:

| Env var | Directive | Default |
|---------|-----------|---------|
| `PHP_FPM_PM` | `pm` | `dynamic` |
| `PHP_FPM_PM_MAX_CHILDREN` | `pm.max_children` | `20` |
| `PHP_FPM_PM_START_SERVERS` | `pm.start_servers` | `2` |
| `PHP_FPM_PM_MIN_SPARE_SERVERS` | `pm.min_spare_servers` | `1` |
| `PHP_FPM_PM_MAX_SPARE_SERVERS` | `pm.max_spare_servers` | `3` |
| `PHP_FPM_PM_MAX_REQUESTS` | `pm.max_requests` | `1000` |

In `dynamic` mode php-fpm requires `min_spare ≤ start_servers ≤ max_spare`, so
raise `PHP_FPM_PM_MAX_SPARE_SERVERS` if you raise `PHP_FPM_PM_START_SERVERS`.

## Logging

All images write their logs to the container's **stdout/stderr**, so `docker logs`
(and your orchestrator's log pipeline) shows everything - no log files inside the
container, nothing to mount or rotate.

| Source | Destination |
|--------|-------------|
| PHP engine errors (all web images) | stderr |
| php-fpm master + worker output (`fpm-nginx`, `fpm-apache`) | stderr (base image default; workers folded in via `catch_workers_output`) |
| php-fpm access log | stderr |
| nginx access / error (`fpm-nginx`) | stdout / stderr |
| Apache access / error (`fpm-apache`) | stdout / stderr |
| Caddy runtime / error (`frankenphp`) | stderr |
| dockerd (`dind`) | stderr (base image default) |

PHP error logging is env-overridable like the rest of `common/php.ini`
(`docker run -e PHP_DISPLAY_ERRORS=On ...`):

| Env var | Directive | Default |
|---------|-----------|---------|
| `PHP_LOG_ERRORS` | `log_errors` | `On` |
| `PHP_ERROR_LOG` | `error_log` | `/proc/self/fd/2` (stderr) |
| `PHP_DISPLAY_ERRORS` | `display_errors` | `Off` |
| `PHP_DISPLAY_STARTUP_ERRORS` | `display_startup_errors` | `Off` |
| `PHP_ERROR_REPORTING` | `error_reporting` | `E_ALL` |

`display_errors` is **Off** by default so errors are never sent to the HTTP response
(they still go to stderr); turn it `On` only for local debugging.

php-fpm logging (fpm images), overriding the base image's stderr defaults:

| Env var | Directive | Default |
|---------|-----------|---------|
| `PHP_FPM_LOG_LEVEL` | `log_level` | `notice` |
| `PHP_FPM_CATCH_WORKERS_OUTPUT` | `catch_workers_output` | `yes` |
| `PHP_FPM_ACCESS_LOG` | `access.log` | `/proc/self/fd/2` (set `/dev/null` to silence) |

Web-server log verbosity:

| Env var | Image | Directive | Default |
|---------|-------|-----------|---------|
| `NGINX_ERROR_LOG_LEVEL` | `fpm-nginx` | nginx `error_log` level | `warn` |
| `APACHE_LOG_LEVEL` | `fpm-apache` | Apache `LogLevel` | `warn` |

`frankenphp`: Caddy sends its runtime/error logs to stderr; HTTP **access** logging is
off by default (Caddy's own default). Enable it by appending a `log` directive via
`CADDY_SERVER_EXTRA_DIRECTIVES` (emits JSON to stderr) - remember to also re-add
`respond /healthz 200` if you override that env var.

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

## Local development: matching the host user

When you bind-mount a project directory, files the container writes should be
owned by *your* host user, not `www-data`, so you can edit them without `sudo`.

- **Docker Desktop (macOS / Windows):** nothing to do. Docker Desktop maps
  bind-mount ownership to your host user automatically.
- **Linux hosts:** the container's uid matters. Two options:
  - **Build-time (recommended, stays non-root):** remap `www-data` to your uid/gid
    ```sh
    make fpm-nginx-alpine USER_ID=$(id -u) GROUP_ID=$(id -g)
    ```
    The image still runs as `www-data`, just with your uid, so files it writes are
    owned by you. Leave `USER_ID` unset for the hardened default (uid 82/33).
  - **Runtime:** `docker run --user "$(id -u):$(id -g)" ...` - no rebuild; s6-overlay
    fixes its own dir ownership on start.

**Security:** this is a local-dev convenience and low-risk *as long as you keep
your uid non-zero* - the images are hardened around running non-root, and setting
`USER_ID=0` would run everything as root and defeat that. Don't publish an image
built with a developer's `USER_ID` to a shared registry/production; build those
with the default. Matching your uid does not add container-escape surface; it only
changes file ownership on mounts.

## Docker Compose

A ready-to-run example (fpm-nginx app + Postgres, with host-user matching and the
`PHP_MEMORY_LIMIT` override) is in
[`docker-compose.example.yml`](docker-compose.example.yml). Run it:

```sh
USER_ID=$(id -u) GROUP_ID=$(id -g) \
  docker compose -f docker-compose.example.yml up --build
```

## Testing

Tests run against a **running** container with
[dgoss](https://github.com/goss-org/goss/tree/master/extras/dgoss): each target
starts the image and checks the `<image>/goss.yaml` in that image's directory.

```sh
make test           # runtime-test every image (Alpine)
make test-fpm-nginx # one image
```

Requires `goss` + `dgoss` on `PATH`. Each image's checks live in its
`<image>/goss.yaml`.

CI (`.github/workflows/ci.yml`) runs on push/PR as a **matrix**: one parallel job
per image × PHP version × arch (`amd64` + `arm64`) × OS (`alpine` + `debian`),
each building and goss-testing that one variant; `dind` is a separate per-arch job.
The PHP version set is per image - a `matrix` job emits it as JSON so build and
push share one list.

On push to **main**, each job's third step pushes the **tested** image to **GHCR**
under a per-arch tag; the `release-php-image`/`release-dind-image` jobs then assemble the
**multi-arch** (amd64+arm64) manifest (`ghcr.io/<owner>/<image>:<tag>`) with
`docker buildx imagetools create`. No QEMU - the published images are exactly the
ones built and goss-tested natively on each arch.

Run the workflow locally with [`act`](https://github.com/nektos/act) (`.actrc`
maps the runner labels):

```sh
act pull_request -j build-php-image --container-options '-v /tmp:/tmp'
```

`-v /tmp:/tmp` lets dgoss's bind-mounts resolve under act's nested docker, and the
`pull_request` event skips the push steps (they need real GHCR auth). Both arch
matrix entries run on your host arch - act can't truly cross-build on one machine.

## Status

Building and runtime-tested (goss): all images.

Notes:
- `fpm-apache` on **Alpine** executes `.php` correctly. Alpine ships mod_proxy in a
  separate `apache2-proxy` package, which the Dockerfile installs, so `proxy_fcgi`
  loads and Apache proxies `.php` to php-fpm just like Debian.
- `dind` is a thin layer over `docker:*-dind-rootless` (Alpine only; there is no
  Debian/rootless upstream, so dind is a single variant).
