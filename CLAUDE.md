# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

A collection of Docker images, each in its own directory with a single `Dockerfile`:

- `fpm-nginx` - PHP-FPM behind nginx
- `fpm-apache` - PHP-FPM with Apache
- `frankenphp` - FrankenPHP
- `dind` - Docker-in-Docker

There is no CI yet. Local builds go through the `Makefile` (see Commands below).

## Naming and tags

See `README.md` for the authoritative scheme. Summary:

- Every image ships Debian and Alpine variants and is multi-arch (`linux/amd64` + `linux/arm64`).
- Architecture is never in the tag — a single tag is a manifest list serving both arches.
- Tag format is `[<version>-]<os>` (`<os>` = `debian` | `alpine`):
  - PHP images (`fpm-nginx`, `fpm-apache`, `frankenphp`): `<php-version>-<os>`, e.g. `8.3-alpine`.
  - `dind`: `<docker-version>-<os>`.
- Registry/namespace is not decided yet; images are named without a prefix.

## Layout and build model

- One directory per image, each with a **single** `Dockerfile`. There are no
  per-OS Dockerfiles.
- Debian vs Alpine is a build-time input, not a separate file:
  - The Makefile passes the base image as the `BASE_IMAGE` build arg (it owns the
    image/OS/version -> tag mapping).
  - `common/helper` is the shared build toolbox, copied to `/usr/local/bin/helper`
    and invoked as `helper <command>`. Use it in Dockerfiles instead of calling
    apt/apk/curl directly.
- The build context is the **repo root** (`docker buildx build -f <image>/Dockerfile .`)
  so every Dockerfile can `COPY common/...`. Do not `cd` into an image dir to build.

### common/helper commands

- `detect-arch` -> `amd64` | `arm64` (canonical, Docker-style; from `uname -m`)
- `detect-os` -> `debian` | `alpine`
- `install-packages <pkgs...>` -> apt-get or apk, with cache cleanup
- `install-s6-overlay` -> s6-overlay init/supervisor (noarch + per-arch tarballs)
- `install-composer` -> Composer to `/usr/local/bin/composer` (sha256-verified)
- `install-pie` -> PIE phar to `/usr/local/bin/pie` (needs PHP at runtime)
- `install-castor` -> Castor static binary to `/usr/local/bin/castor`
Each tool has an enabling and a non-enabling variant; every arg is an extension
(multiple allowed):

- `install-pie-ext` / `install-pie-skip-enable-ext` -> `pie install`
  (composer-style `vendor/ext` names)
- `install-pecl-ext` / `install-pecl-skip-enable-ext` -> `pecl install`
  (the enabling variant also runs `docker-php-ext-enable`)
- `install-docker-ext` / `install-docker-skip-enable-ext` -> `docker-php-ext-install`

How "skip enable" is implemented differs per tool: pie has a native
`--skip-enable-extension` flag; pecl simply omits the enable call; docker removes
the generated `conf.d/docker-php-ext-<ext>.ini` (docker-php-ext-install always
enables). Build/runtime deps ($PHPIZE_DEPS, `-dev` libs) are the caller's
responsibility, as in the official php image docs.

Pinning an extension version (the token is passed straight through):
- pecl: `redis-6.1.0` (name-version). The enable step strips the version.
- pie: `asgrim/example-pie-extension:2.0.8` (composer `vendor/name:constraint`).
- docker: not possible - `docker-php-ext-install` builds extensions bundled in
  the PHP source, so their version tracks the base image; pin `PHP_VERSION` instead.

Tool versions are pinned at the top of `common/helper` (`S6_OVERLAY_VERSION`,
`COMPOSER_VERSION`, `PIE_VERSION`, `CASTOR_VERSION`) and overridable via env.
Keep them pinned - do not switch to "latest" URLs (reproducibility).
- Where the distro layout genuinely diverges (Apache config tree/control binary,
  presence of `dockerd`), the Dockerfile branches at build time by detecting the
  distro (e.g. `command -v a2enmod`, `command -v dockerd`) rather than templating.

## Commands

```sh
make build              # all images, both OS variants
make <image>            # e.g. make fpm-nginx (both variants)
make <image>-<os>       # e.g. make fpm-nginx-alpine (single variant)
make help               # list targets
```

Variables: `PHP_VERSION` (default 8.4), `DOCKER_VERSION` (default 29), `REGISTRY`
(tag prefix), `PLATFORM` (empty = host arch). Local builds use `--load` and are
host-arch only; multi-arch is a push-time concern and is not in the Makefile yet.

## Testing

Tests run against a **running** container only (no static image tests). `make test`
(and `make test-<image>`) starts each image and probes it with goss via dgoss,
reading `<image>/goss.yaml`. Runs the Alpine tag.

- Requires `goss` + `dgoss` on PATH (the target prints an install hint if absent);
  on macOS also set `GOSS_PATH` to a Linux goss binary. dind runs `--privileged`.
- What each checks: fpm-nginx (php-fpm+nginx running, `memory_limit`==128M, GET
  `/ping.php`→404), fpm-apache (php-fpm running, `memory_limit`==128M, GET `/`→403),
  frankenphp (`memory_limit`==128M, GET `/`→308 Caddy redirect), dind (dockerd
  running, `docker version` reaches the daemon).
- Gotchas: goss renders the whole goss.yaml (comments too) as a Go template, so
  never put `{{ }}` in it - e.g. don't use `docker ... --format` with a template;
  use `docker version` + exit-status instead. Use goss `http` not a raw `port`
  check for the web images - Apache binds IPv6 on Alpine but IPv4 on Debian, so a
  single `tcp:80` line can't cover both, and http also tests serving end-to-end.
  For fpm-apache, don't check the web-server process by name (httpd on Alpine,
  apache2 on Debian).

## PHP configuration (common/php.ini)

The PHP images copy `common/php.ini` to `$PHP_INI_DIR/conf.d/zz-common.ini`. PHP
expands `${...}` in ini files from the environment at parse time and supports a
`${VAR:-default}` fallback (verified on 8.4), so config is env-overridable at
runtime with no rebuild - e.g. `memory_limit = ${PHP_MEMORY:-128M}`, overridden
by `docker run -e PHP_MEMORY=512M`. The default lives in the ini (not in a
Dockerfile `ENV`); do not use a bare `${VAR}` (empty value makes PHP warn and
fall back to 128M). To add a knob: add `key = ${ENV_VAR:-default}` to
`common/php.ini` - no Dockerfile change. Not applied to `dind` (not a PHP image).

## Per-image notes

- `fpm-nginx`, `fpm-apache`: `php:*-fpm[-alpine]` base + web server installed via
  the helper. PID 1 is s6-overlay (`ENTRYPOINT ["/init"]`, installed by
  `helper install-s6-overlay`). Services are s6-rc.d longruns under
  `<image>/s6-rc.d/` (php-fpm + the web server), COPYed into
  `/etc/s6-overlay/s6-rc.d`. php-fpm's run script uses `#!/command/with-contenv sh`
  so `${PHP_MEMORY}` still reaches it at runtime.
  php-fpm listens on 127.0.0.1:9000. Note: setting `ENTRYPOINT` reset the base
  image's inherited `CMD ["php-fpm"]` to empty, so /init runs only the services.
- `frankenphp`: `dunglas/frankenphp:php<ver>-bookworm|-alpine` base; upstream
  entrypoint already serves `/app`.
- `dind`: Alpine = thin layer over `docker:*-dind`; Debian installs the engine
  via `get.docker.com`. `dind/entrypoint.sh` unifies startup. **First cut** - the
  Debian path is not version-pinned (not reproducible yet).

## Status

Building and smoke-tested: `fpm-nginx` (serves PHP), `frankenphp`.
First cut needing iteration: `fpm-apache` (Alpine best-effort), `dind` (Debian
engine install, not pinned).
