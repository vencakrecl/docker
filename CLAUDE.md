# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

A collection of Docker images, each in its own directory with a single `Dockerfile`:

- `fpm-nginx` - PHP-FPM behind nginx
- `fpm-apache` - PHP-FPM with Apache
- `frankenphp` - FrankenPHP
- `dind` - Docker-in-Docker (rootless)

There is no CI yet. Local builds go through the `Makefile` (see Commands below).

## Naming and tags

See `README.md` for the authoritative scheme. Summary:

- Every image ships Debian and Alpine variants and is multi-arch (`linux/amd64` + `linux/arm64`).
- Architecture is never in the tag — a single tag is a manifest list serving both arches.
- Tag format is `[<version>-]<os>` (`<os>` = `debian` | `alpine`):
  - PHP images (`fpm-nginx`, `fpm-apache`, `frankenphp`): `<php-version>-<os>`, e.g. `8.3-alpine`.
  - `dind`: `<docker-version>-rootless` (single variant; no OS suffix - it is
    meaningless for dind, and `-rootless` names the meaningful trait).
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
- `set-user-id <user> <uid> [gid]` -> rewrites the user's uid/gid in
  /etc/passwd + /etc/group (distro-agnostic; Alpine has no usermod). Run it
  *before* the image's `chown -R <user>` so the chown uses the new id.
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
- What each checks: the web images assert `runs-as-non-root` (`id -u` not 0), PHP
  CLI executes (`php -r 'echo 40+2'`→42), and that the shared hello-world
  `common/index.php` is served at `/` on `:8080` (200 + body `Hello, World!`,
  proving PHP executes end-to-end through the web server); fpm images also check
  php-fpm/nginx processes.
- Config is verified via one `env-*` test per env var (no separate default-value
  checks - they were redundant): set the var *inline* in the goss `exec`
  (`env PHP_FPM_PM_MAX_CHILDREN=40 php-fpm -tt`) and assert the effect. This works
  in the default container - no restart with `-e` needed - because php and
  `php-fpm -tt` re-parse config on every invocation. These also prove the shared
  config is loaded (e.g. 40 vs the base image's hardcoded 5) and valid (exit 0).
  php.ini values are read off `php -r`'s stdout; php-fpm values off `php-fpm -tt`'s
  stderr. Keep override values within php-fpm's dynamic constraints
  (min_spare <= start <= max_spare). dind: runs-as-non-root (rootless, uid 1000),
  dockerd running, and `docker version` reaches the rootless daemon socket.
- Gotchas: goss renders the whole goss.yaml (comments too) as a Go template, so
  never put `{{ }}` in it - e.g. don't use `docker ... --format` with a template;
  use `docker version` + exit-status instead. Non-root check: `id -u` with
  `stdout: ["!/^0$/"]` (goss `!` negation + regex). Use goss `http` not a raw
  `port` check for the web images - Apache binds IPv6 on Alpine but IPv4 on Debian,
  and http also tests serving end-to-end. For fpm-apache, don't check the
  web-server process by name (httpd on Alpine, apache2 on Debian).

## CI

`.github/workflows/ci.yml` (push + PR), no lint:
- `matrix` job: single source of truth for the image x PHP-version `targets` list,
  emitted as one-line JSON to `$GITHUB_OUTPUT` (a multi-line value would need the
  `<<DELIM` format). `build-php-image` and `release-php-image` both consume it via
  `${{ fromJSON(needs.matrix.outputs.targets) }}` - edit versions in one place.
- `build-php-image` job: matrix of `arch` (amd64 / arm64) x `os` (alpine / debian) x
  `target` - one job per variant (targets x 2 arch x 2 os). Each runs on the matching runner
  (`ubuntu-latest` / `ubuntu-24.04-arm`), installs goss/dgoss for that arch
  (`dpkg --print-architecture`), then separate steps: **Build**
  (`make <image>-<os> PHP_VERSION=<php>`), **Test** (`dgoss run <image>:<php>-<os>`),
  and on main **Push** (see below). `IMAGE`/`PHP`/`OS`/`REF` are job-level `env`
  (matrix context is available there). Native arch builds (no QEMU) so goss can run
  the container. `fail-fast: false`; goss pinned via `GOSS_VERSION`.
- `build-dind-image` job: per-arch, `make test-dind` (single rootless variant, no
  PHP version), then the same Push step.
- Push is the **third step** of build-php-image / build-dind-image (on main only,
  gated by `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`; the
  jobs carry `packages: write` + a GHCR login step). It `docker tag`+`push`es the
  *already-tested* image to a per-arch tag `ghcr.io/<owner>/<image>:<tag>-<arch>` -
  no rebuild.
- `release-php-image` / `release-dind-image` jobs (`needs: build-php-image` /
  `build-dind-image`, `if: main`): assemble the per-arch tags into the final
  multi-arch tag with `docker buildx imagetools create -t <tag> <tag>-amd64
  <tag>-arm64`. Downside: the `-amd64`/`-arm64` tags linger in the registry (the
  merged `<tag>` is the clean multi-arch one).
- The s6 `run` scripts carry `# shellcheck shell=sh` (for the `with-contenv`
  shebang) - kept even though lint was dropped, in case it's re-added.
- Run the workflow locally with `act` (nektos/act); `.actrc` maps the runner
  labels (incl. the non-standard `ubuntu-24.04-arm`) to a host-arch runner image.
  act binds the host docker socket, so `docker buildx`/`dgoss` hit the host daemon;
  the arch matrix is not truly cross-arch locally (both run on the host arch).

## PHP configuration (common/php.ini, common/php-fpm.conf)

The PHP images copy `common/php.ini` to `$PHP_INI_DIR/conf.d/zz-common.ini`. PHP
expands `${...}` in ini files from the environment at parse time and supports a
`${VAR:-default}` fallback (verified on 8.4), so config is env-overridable at
runtime with no rebuild - e.g. `memory_limit = ${PHP_MEMORY_LIMIT:-128M}`, overridden
by `docker run -e PHP_MEMORY_LIMIT=512M`. The default lives in the ini (not in a
Dockerfile `ENV`); do not use a bare `${VAR}` (empty value makes PHP warn and
fall back to 128M). To add a knob: add `key = ${ENV_VAR:-default}` to
`common/php.ini` - no Dockerfile change. Not applied to `dind` (not a PHP image).

The **fpm** images (fpm-nginx, fpm-apache) additionally copy `common/php-fpm.conf`
to `/usr/local/etc/php-fpm.d/zzz-common.conf` (the `zzz-` prefix makes it load
after the base `www.conf`/`zz-docker.conf`; php-fpm merges `[www]` across files, so
ours wins). php-fpm's config parser *also* supports `${VAR:-default}` (verified),
driving `PHP_FPM_PM*` env vars (pm, max_children, start_servers, min/max_spare,
max_requests). frankenphp embeds PHP (no php-fpm), so it doesn't get this file.
Gotcha: dynamic pm requires `min_spare <= start_servers <= max_spare` or php-fpm
refuses to start - the env overrides are interdependent.

## Per-image notes

- `fpm-nginx`, `fpm-apache`: `php:*-fpm[-alpine]` base + web server installed via
  the helper. PID 1 is s6-overlay (`ENTRYPOINT ["/init"]`, installed by
  `helper install-s6-overlay`). Services are s6-rc.d longruns under
  `<image>/s6-rc.d/` (php-fpm + the web server), COPYed into
  `/etc/s6-overlay/s6-rc.d`. php-fpm's run script uses `#!/command/with-contenv sh`
  so `${PHP_MEMORY_LIMIT}` still reaches it at runtime.
  php-fpm listens on 127.0.0.1:9000. Note: setting `ENTRYPOINT` reset the base
  image's inherited `CMD ["php-fpm"]` to empty, so /init runs only the services.
- **Non-root (secure by default):** the web images run unprivileged as `www-data`
  on port **8080** (`USER www-data`, `EXPOSE 8080`). s6-overlay has "limited"
  non-root support that works here because there are only two services and no
  fix-attrs/loggers/syslogd. Requirements: the runtime dirs must be writable by
  www-data - `chown -R www-data /run <server dirs>` (nginx: `/var/lib/nginx`
  `/var/log/nginx` which is a symlink `chown -R` won't follow; apache: switch
  `Listen 80`→`8080` and `User/Group` to www-data per distro, chown
  `/var/log/apache2`). frankenphp uses `ENV SERVER_NAME=:8080` (plain HTTP, no
  443/auto-TLS) and chowns `/app /config /data`.
- **Host-user matching (local dev):** the web images take `USER_ID`/`GROUP_ID`
  build args; when set they `helper set-user-id www-data ...` *before* the chown,
  so www-data gets the host uid and bind-mounted files are owned correctly (matters
  on Linux; Docker Desktop auto-maps). Makefile passes them only when set (so no
  build warning on dind). Default unset = hardened uid 82/33. Runtime alternative:
  `docker run --user $(id -u):$(id -g)` (s6-overlay fixes its dir ownership on start).
- **Document root (`SERVER_ROOT`, runtime-overridable):** all three web images
  expose `SERVER_ROOT` (default fpm-nginx/fpm-apache `/var/www/html`, frankenphp
  `/app/public`) so the docroot can be changed with `docker run -e SERVER_ROOT=...`
  (mount your app there). Wiring differs by server: frankenphp's Caddyfile reads it
  natively (`root {$SERVER_ROOT:public/}`); Apache expands `${SERVER_ROOT}` in
  `vhost.conf` at config-parse time; nginx *cannot* expand env vars, so `nginx.conf`
  ships as `nginx.conf.template` and the nginx s6 run script renders `${SERVER_ROOT}`
  into `/run/nginx.conf` (via `sed`, only that token - `$uri`/`$document_root` are
  left intact) and starts `nginx -c /run/nginx.conf`. The shared hello-world
  `common/index.php` is COPYed into each default docroot.
- `frankenphp`: `dunglas/frankenphp:php<ver>-bookworm|-alpine` base; serves
  `/app/public` (the base Caddyfile's `SERVER_ROOT`, defaulted here to `/app/public`).
- `dind`: thin layer over `docker:*-dind-rootless` (daemon runs as the `rootless`
  user, uid 1000, via rootlesskit). Alpine-only upstream, so dind is a single
  variant (no debian/alpine split). Base entrypoint/CMD/USER inherited; run the
  container with `--privileged`. The rootless daemon socket is
  `/run/user/1000/docker.sock`, so a CLI needs `DOCKER_HOST` pointed there.

## Status

Building and runtime-tested (goss): all images. Known gap: `fpm-apache` on Alpine
serves `.php` as source (mod_proxy in a separate `apache2-proxy` package not
installed); Debian apache is fine.
