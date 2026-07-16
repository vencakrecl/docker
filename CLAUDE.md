# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

A collection of Docker images, each in its own directory with a single `Dockerfile`:

- `fpm-nginx` - PHP-FPM behind nginx
- `fpm-apache` - PHP-FPM with Apache
- `frankenphp` - FrankenPHP
- `dind` - Docker-in-Docker (rootless)

Local builds go through the `Makefile` (see Commands); CI
(`.github/workflows/ci.yml`) builds, goss-tests and publishes to GHCR (see CI).

User-facing docs: `README.md` is a short landing page; the detail lives in `docs/`
(`tags.md`, `configuration.md`, `building.md`, `testing.md`). Keep them in sync when
behaviour changes - `docs/configuration.md` in particular is the full env-var reference.

## Naming and tags

See `docs/tags.md` for the authoritative scheme. Summary:

- Every image ships Debian and Alpine variants and is multi-arch (`linux/amd64` + `linux/arm64`).
- Architecture is never in the tag — a single tag is a manifest list serving both arches.
- Tag format is `[<version>-]<os>` (`<os>` = `debian` | `alpine`):
  - PHP images (`fpm-nginx`, `fpm-apache`, `frankenphp`): `<php-version>-<os>`, e.g. `8.3-alpine`.
  - `dind`: `<docker-version>-rootless` (single variant; no OS suffix - it is
    meaningless for dind, and `-rootless` names the meaningful trait). Optional
    cloud-CLI variants add a `-<cloud>` suffix: `<docker-version>-rootless-<aws|gcloud|azure>`
    (selected by the `CLOUD` build arg; see the Cloud CLI variants section).
  - Dev variant of the web images: `<php-version>-<os>-dev` (e.g. `8.4-alpine-dev`);
    `-dev` names the trait (adds the dev toolbox), same as `-rootless` for dind. See
    the Dev image variant section.
- Registry/namespace is not decided yet; images are named without a prefix.

## Layout and build model

- One directory per image, each with a **single** `Dockerfile`. There are no
  per-OS Dockerfiles. The three web images' Dockerfiles are **multi-stage**: a `base`
  stage (all the prod build steps), a `dev` stage that layers the dev toolbox on top
  (`--target dev`), and a trailing empty `prod` stage (`FROM base`) kept *last* so a
  plain `docker build`/compose with no `--target` still yields the lean prod image.
- **Section markers.** Dockerfiles are organised with paired, foldable comment markers
  `###> SECTION NAME` … `###< SECTION NAME` (uppercase; convention borrowed from the
  internal php-base repo). The stage wrappers are `BASE IMAGE` / `DEV IMAGE` / `PROD IMAGE`,
  nesting sub-sections (`RUNTIME DEPS`, `PHP EXTENSIONS`, `SERVER SETTINGS`,
  `PHP [& FPM] CONFIGURATION`, `NON-ROOT USER`, `ENTRYPOINT & RUNTIME METADATA`). Keep the
  markers balanced when editing. Prose comments are otherwise kept minimal - only genuinely
  non-obvious rationale (e.g. the s6 SIGTERM shutdown gotcha) survives.
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
- `install-runtime-deps <pkgs...>` -> apt-get or apk, with cache cleanup
- `install-build-deps <pkgs...>` / `remove-build-deps` -> install the given packages as
  a removable group, then drop what was added. The caller (the Dockerfile) passes the
  packages - the toolchain (`$PHPIZE_DEPS`, an image ENV), `unzip`, and any headers.
  Alpine: an `apk --virtual` group, dropped whole. Debian: only the packages it *newly*
  installed are recorded and `apt-get purge --auto-remove`d, so already-present ones
  (base `$PHPIZE_DEPS`, a runtime pkg) survive. Either way the transient build packages
  leave no trace (Debian keeps its base toolchain, which it owns).
- `install-s6-overlay` -> s6-overlay init/supervisor (noarch + per-arch tarballs)
- `install-composer` -> Composer to `/usr/local/bin/composer` (sha256-verified)
- `install-pie` -> PIE phar to `/usr/local/bin/pie` (needs PHP at runtime)
- `install-castor` -> Castor static binary to `/usr/local/bin/castor`
- `install-aws-cli` / `install-gcloud` / `install-azure-cli` -> cloud CLIs for the
  `dind` variants (Alpine only, since the dind base is Alpine): aws via apk community;
  gcloud from the versioned tarball with system musl python3 (bundled glibc python
  dropped) + bash/libc6-compat; azure via pip into a `/opt/azure-cli` venv (`az` on
  PATH) from the hash-verified lockfile `dind/azure-cli-requirements.txt` (COPYed to
  `/usr/local/etc/`, `pip --require-hashes`), toolchain installed/removed as a build-deps group.
Each installs + enables the extension(s); every arg is an extension name (multiple
allowed):

- `install-pie-ext` -> `pie install` (composer-style `vendor/ext` names)
- `install-pecl-ext` -> `pecl install` (then `docker-php-ext-enable`)
- `install-docker-ext` -> `docker-php-ext-install`

Build/runtime deps ($PHPIZE_DEPS, `-dev` libs) are the caller's responsibility, as in
the official php image docs.

Pinning an extension version (the token is passed straight through):
- pecl: `redis-6.1.0` (name-version). The enable step strips the version.
- pie: `asgrim/example-pie-extension:2.0.8` (composer `vendor/name:constraint`).
- docker: not possible - `docker-php-ext-install` builds extensions bundled in
  the PHP source, so their version tracks the base image; pin `PHP_VERSION` instead.

Tool versions are pinned at the top of `common/helper` (`S6_OVERLAY_VERSION`,
`COMPOSER_VERSION`, `PIE_VERSION`, `CASTOR_VERSION`, `GCLOUD_VERSION`,
`AZURE_CLI_VERSION`; AWS CLI is unpinned - it tracks the Alpine repo) and overridable via env.
Keep them pinned - do not switch to "latest" URLs (reproducibility).

Downloaded artifacts are **sha256-verified** before use (via the `_verify_sha256` helper),
against digests **pinned in `common/helper`** - never a checksum fetched from the same origin
as the artifact (a compromised/MITM'd origin could serve a matching malicious artifact+sidecar
pair; trust-on-first-use). s6-overlay (`S6_OVERLAY_SHA256_{NOARCH,AMD64,ARM64}`), composer
(`COMPOSER_SHA256`), pie (`PIE_SHA256`), castor (`CASTOR_SHA256_<ARCH>`) and gcloud
(`GCLOUD_SHA256_<ARCH>`) all pin their digest next to the version.
Like the `*_VERSION` pins these are helper env vars, not wired as Dockerfile `ARG`s, so a plain
`docker build` uses the defaults; if you do override a version (set the env when invoking helper,
or add an `ARG`), set the matching `*_SHA256` too or verification fails - bump both together. Azure CLI installs via pip
under `--require-hashes` from `dind/azure-cli-requirements.txt`, a lockfile pinning its whole
transitive tree to exact versions + PyPI sha256; regenerate it with `dind/gen-azure-hashes.sh`
after bumping `AZURE_CLI_VERSION` (the version lives in the lockfile). AWS CLI is an apk package (verified by apk). The verifier is
exposed as `helper verify-sha256 <file> <sha256>`; CI reuses it to check its goss binary (against
the pinned per-arch `GOSS_SHA256_{AMD64,ARM64}`) and the `dgoss` script (pinned via `DGOSS_SHA256`).

**Dependency automation.** These hand-pinned versions are kept fresh by three cooperating
pieces (Dependabot only covers github-actions - `FROM ${BASE_IMAGE}` and the helper pins
aren't tracked ecosystems):
- **Renovate** (`.github/renovate.json`) opens version-bump PRs for s6-overlay/composer/pie/castor
  (annotated with `# renovate:` comments in `common/helper`) and goss (in `ci.yml`), via a
  custom regex manager keyed off those comments. It cannot recompute artifact digests, so a
  bump PR carries a note to run `make bump-digests` (CI fails closed on the stale digest otherwise).
- **`scripts/deps.sh`** (`make check-deps` / `make bump-digests`): `check` reports pinned-vs-latest
  for every tool incl. gcloud + azure-cli (which have no standard Renovate datasource);
  `refresh-digests [tool...]` re-fetches each artifact at its currently-pinned version and rewrites
  the matching `*_SHA256` in `common/helper` / `ci.yml` (uses `cat >` not `mv` so `helper`'s 0755
  mode survives). "Verify digests" = `refresh-digests` + `git diff --exit-code`.
- **`.github/workflows/deps-check.yml`** runs `deps.sh check` weekly (Mon 06:00 UTC) and opens/updates
  a single `Outdated pinned dependencies` issue via `gh` when anything is behind (`exit 3`).
- Base-image tags (`PHP_VERSION`/`DOCKER_VERSION`) are intentionally not automated: they're policy
  floors, and OS security patches arrive on every rebuild since the `FROM` tags aren't digest-pinned.
- Where the distro layout genuinely diverges (e.g. the Apache config tree, or
  per-distro packages/headers), the Dockerfile branches at build time on `helper
  detect-os` (`debian`|`alpine`) rather than templating - e.g. fpm-apache's `case`
  picking the Debian `a2enmod` path vs the Alpine `httpd.conf` sed, and the web images'
  `PHP EXTENSIONS` blocks selecting per-distro `build_deps`.

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
  php-fpm/nginx processes. Each web image also has a `healthcheck` command test
  running the `/usr/local/bin/healthcheck` probe (exit 0), which is the same script
  the `HEALTHCHECK` directive runs (see the Health checks section).
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
  **`variant` (prod / dev)** x `target` (targets x 2 x 2 x 2 jobs). Each runs on the
  matching runner (`ubuntu-latest` / `ubuntu-24.04-arm`), installs goss/dgoss for that
  arch (`dpkg --print-architecture`), then separate steps: **Build**
  (`make $MAKE_TARGET PHP_VERSION=<php>`, where `MAKE_TARGET`/`TAG` carry the `-dev`
  suffix for the dev variant), **Test** (`dgoss run <image>:$TAG` - the dev variant runs
  the image's own `<image>/goss.dev.yaml` via `GOSS_FILE`), **Graceful stop**, and on main **Push** (see
  below). `IMAGE`/`PHP`/`OS`/`VARIANT`/`MAKE_TARGET`/`TAG`/`REF` are job-level `env`
  (matrix context is available there). Native arch builds (no QEMU) so goss can run
  the container. `fail-fast: false`; goss pinned via `GOSS_VERSION`.
- `build-dind-image` job: matrix of `arch` x `suffix` (`""` | `-aws` | `-gcloud` |
  `-azure`), running `make test-dind$SUFFIX` (no PHP version), then the same Push step
  (per-arch tag `<docker>-rootless$SUFFIX-<arch>`). `release-dind-image` carries the
  same `suffix` matrix so each variant gets its multi-arch manifest.
- Push is the **third step** of build-php-image / build-dind-image (on main only,
  gated by `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`; the
  jobs carry `packages: write` + a GHCR login step). It `docker tag`+`push`es the
  *already-tested* image to a per-arch tag `ghcr.io/<owner>/<image>:<tag>-<arch>` -
  no rebuild.
- **Docker Hub mirror (optional):** every GHCR push/manifest step is shadowed by an
  equivalent `docker.io/<DOCKERHUB_USERNAME>/<image>:<tag>` step, each guarded by
  `vars.DOCKERHUB_USERNAME != ''` (build jobs also keep the main-only gate; the
  release-job steps guard on the var only, since the job is already main-gated). So
  Docker Hub is pushed **only when** the repo variable `DOCKERHUB_USERNAME` (namespace +
  login user) is set and the `DOCKERHUB_TOKEN` secret exists; unset = the steps skip and
  CI is unaffected. Same per-arch tag + `imagetools create` merge as GHCR.
- `release-php-image` / `release-dind-image` jobs (`needs: build-php-image` /
  `build-dind-image`, `if: main`): assemble the per-arch tags into the final
  multi-arch tag with `docker buildx imagetools create -t <tag> <tag>-amd64
  <tag>-arm64`. `release-php-image` carries the same `os` x `variant` x `target` matrix,
  so both `<php>-<os>` and `<php>-<os>-dev` get their multi-arch manifest. Downside: the
  `-amd64`/`-arm64` tags linger in the registry (the merged `<tag>` is the clean
  multi-arch one).
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
`common/php.ini` *and* an `env-*` goss test in each web image. Not applied to `dind`
(not a PHP image). Current knobs (all defaulting to PHP's own defaults, bar an explicit
UTC timezone): `PHP_MEMORY_LIMIT` (128M), `PHP_UPLOAD_MAX_FILESIZE` (2M),
`PHP_POST_MAX_SIZE` (8M), `PHP_MAX_INPUT_VARS` (1000), `PHP_DATE_TIMEZONE` (UTC),
`PHP_OPCACHE_MEMORY_CONSUMPTION` (128), `PHP_OPCACHE_MAX_ACCELERATED_FILES` (10000),
`PHP_OPCACHE_INTERNED_STRINGS_BUFFER` (8), `PHP_OPCACHE_VALIDATE_TIMESTAMPS` (1),
`PHP_OPCACHE_ENABLE_CLI` (0; enable OPcache for the CLI SAPI - for long-running CLI
workers), `PHP_OPCACHE_PRELOAD` (empty = off; a path enables OPcache preloading, e.g.
Symfony's `config/preload.php`), `PHP_OPCACHE_PRELOAD_USER` (www-data; only applies when
preload is set, must match `SERVER_USER`), `PHP_REALPATH_CACHE_SIZE` (4096K),
`PHP_REALPATH_CACHE_TTL` (120). Each has an `env-*`
goss test that sets it inline and asserts `ini_get` (for preload the CLI's
`opcache.enable_cli=0` means the path is parsed but not actually loaded, so the test is
safe with any path). The `examples/<fw>` composes tune
PHP per framework purely through these env vars (no mounted `php.ini`). The Symfony
example ships the preload/validate-timestamps knobs commented out as a documented
production profile (preloading snapshots code at start, so it fights the mounted RW
dev app - see `examples/symfony/docker-compose.yml`).

`SERVER_TIMEOUT` (seconds, image ENV default **30**, same `SERVER_*` family as
`SERVER_ROOT`/`SERVER_USER`) is the single request time budget: `common/php.ini` sets
`max_execution_time = ${SERVER_TIMEOUT}` *and* the web servers use it as their backend
timeout, so PHP's limit and the proxy stay aligned by construction (the proxy waits
exactly as long as PHP may run - no "raise both"). **fpm-nginx** renders it into
`fastcgi_read_timeout` in the nginx run script (a goss test asserts the default 30s in
`/run/nginx.conf`); **fpm-apache** expands `${SERVER_TIMEOUT}` in `vhost.conf`'s
`ProxyTimeout`; **frankenphp** has no FastCGI proxy, but `max_execution_time` still caps
requests there. Every web image therefore declares `ENV SERVER_TIMEOUT=30` (the shared
php.ini needs it defined). Must be a positive integer for the fpm images: a backend
timeout of 0 is invalid (nginx reads `fastcgi_read_timeout 0` as *time out immediately*;
Apache's `ProxyTimeout` must be >= 1), so their run scripts reject 0/non-numeric with a
clear error; on frankenphp `SERVER_TIMEOUT=0` just means `max_execution_time=0`
(unlimited PHP), which is valid. Note the CLI SAPI forces `max_execution_time` to 0, so
that value isn't `ini_get`-testable (unlike the other php.ini knobs).

The **fpm** images (fpm-nginx, fpm-apache) additionally copy `common/php-fpm.conf`
to `/usr/local/etc/php-fpm.d/zzz-common.conf` (the `zzz-` prefix makes it load
after the base `www.conf`/`zz-docker.conf`; php-fpm merges `[www]` across files, so
ours wins). php-fpm's config parser *also* supports `${VAR:-default}` (verified),
driving `PHP_FPM_PM*` env vars (pm, max_children, start_servers, min/max_spare,
max_requests). frankenphp embeds PHP (no php-fpm), so it doesn't get this file.
Gotcha: dynamic pm requires `min_spare <= start_servers <= max_spare` or php-fpm
refuses to start - the env overrides are interdependent.

## Logging

Every image logs to the container's **stdout/stderr** (12-factor; visible in `docker
logs`). No log files inside the container. Wiring per source, and what is env-overridable:

- **PHP engine (`common/php.ini`):** the shared php.ini now sets error logging (it set
  none before), all env-driven like the other knobs: `PHP_LOG_ERRORS` (On),
  `PHP_ERROR_LOG` (`/proc/self/fd/2` = stderr), `PHP_DISPLAY_ERRORS` (**Off** - never leak
  errors into the HTTP response; still logged to stderr), `PHP_DISPLAY_STARTUP_ERRORS`
  (Off), `PHP_ERROR_REPORTING` (`E_ALL`). To add a knob: same recipe as the other php.ini
  settings (add `key = ${ENV:-default}` + an `env-*` goss test). Note `error_reporting`'s
  *numeric* value is PHP-version-specific (E_ALL differs across versions), so the goss test
  sets a fixed number (`PHP_ERROR_REPORTING=0`) rather than asserting E_ALL's integer.
- **php-fpm (`common/php-fpm.conf`, fpm images):** the base `php:*-fpm` image already ships
  `docker.conf` with `error_log = /proc/self/fd/2`, `access.log = /proc/self/fd/2`,
  `catch_workers_output = yes`, `decorate_workers_output = no` - so FPM + PHP worker output
  already reach stderr. Our `zzz-common.conf` (loads last, wins) just re-declares the key
  ones as env knobs: `PHP_FPM_LOG_LEVEL` (notice, in a `[global]` block),
  `PHP_FPM_CATCH_WORKERS_OUTPUT` (yes), `PHP_FPM_ACCESS_LOG` (`/proc/self/fd/2`; set
  `/dev/null` to silence). frankenphp has no php-fpm, so it doesn't get this file.
- **nginx (`fpm-nginx`):** `nginx.conf` already used `/dev/stdout` (access) + `/dev/stderr`
  (error); the error level is now a `${NGINX_ERROR_LOG_LEVEL}` template placeholder rendered
  by the nginx s6 run script (default `warn`), same mechanism as `${SERVER_ROOT}` /
  `${FASTCGI_READ_TIMEOUT}` (nginx can't expand env itself).
- **Apache (`fpm-apache`):** was the one gap - Apache logged to files under
  `/var/log/apache2`. Now `vhost.conf` ships `ErrorLog /dev/stderr` (global scope, last-wins
  over the base default) + `CustomLog /dev/stdout combined` (in the vhost) + `LogLevel
  ${APACHE_LOG_LEVEL}`. `APACHE_LOG_LEVEL` is a Dockerfile `ENV` (default `warn`) because
  httpd's `${VAR}` expansion has **no** shell-style `:-default` (unlike PHP/nginx-run) -
  same as `${SERVER_TIMEOUT}`/`${SERVER_ROOT}`. The distro-default file logs are neutralized
  in the Dockerfile: Debian `a2disconf other-vhosts-access-log` (its `CustomLog`
  *accumulates*, so disabling it prevents a file + double-log); Alpine comments out
  `httpd.conf`'s stock `CustomLog` (it also accumulates) via a one-line sed - the std-stream
  `ErrorLog`/`CustomLog` are then supplied by the shared vhost (`ErrorLog` global last-wins,
  `CustomLog` in the vhost). The `/var/log/apache2` chown was dropped (nothing writes there now).
- **Caddy (`frankenphp`):** ships its own `frankenphp/Caddyfile`, COPYed to
  `/etc/frankenphp/Caddyfile` (where the base CMD's `--config` already points). It trims the
  upstream Mercure/Vulcain boilerplate and keeps the base's env knobs overridable
  (`SERVER_NAME`, `SERVER_ROOT`, `CADDY_GLOBAL_OPTIONS`, `FRANKENPHP_CONFIG`,
  `CADDY_EXTRA_CONFIG`, and the `{$CADDY_SERVER_EXTRA_DIRECTIVES}` placeholder). Caddy's
  runtime/error logs go to stderr by default; HTTP **access** logging is off by default
  (Caddy's own default). Opt in by appending `log` to `CADDY_SERVER_EXTRA_DIRECTIVES` (JSON
  to stderr; the escape hatch is now empty by default - see Health checks). PHP app errors
  still reach stderr via the shared php.ini.
- **dind:** dockerd logs to stderr (base image default); not touched.

Goss (per the repo's `env-*` pattern): the five php.ini error knobs get `ini_get` tests in
all three web `goss.yaml` (identical block); the three FPM knobs get `php-fpm -tt` stderr
tests in the two fpm files. Gotcha - the web-server log settings can't be re-rendered inline
in a goss `exec` (nginx renders `/run/nginx.conf` once at start; Apache parses env once), so
those tests assert the **rendered/shipped config** (`nginx-error-log-level` greps
`/run/nginx.conf`; `apache-logs-to-std-streams` greps `/etc/apache2/fpm-vhost.conf` for
`/dev/stdout`+`/dev/stderr`) rather than an env override - same limitation as the existing
`nginx-fastcgi-read-timeout` test.

## Health checks

Every image ships a Docker `HEALTHCHECK` (`--interval=30s --timeout=5s --retries=3`).
Modelled on serversideup/docker-php: web images probe an HTTP endpoint, dind probes
the daemon.

- **Web images (fpm-nginx, fpm-apache, frankenphp):** `HEALTHCHECK CMD ["healthcheck"]`
  runs `common/healthcheck` (copied to `/usr/local/bin/healthcheck`), which HTTP-GETs
  `http://127.0.0.1:${HEALTHCHECK_PORT:-8080}${HEALTHCHECK_PATH}` and exits 0 only on
  2xx/3xx (curl, with a PHP `file_get_contents` fallback - both present in the base).
  `HEALTHCHECK_PATH` defaults to **`/healthz`**, a cheap, app-independent liveness
  endpoint (like serversideup's `/healthcheck`): the **fpm images** back it with
  php-fpm's **ping** (`ping.path=/healthz`, `ping.response=pong` in `common/php-fpm.conf`;
  nginx via a `location = /healthz`, apache via `ProxyPass "/healthz"`), so FPM answers
  200 itself without running any PHP script; **frankenphp** has no FPM, so its
  `frankenphp/Caddyfile` answers with a static `respond /healthz 200` in the site block
  (before `php_server`). Healthy therefore means the web server + PHP
  runtime accept connections - it does **not** prove the app executes. `start-period=10s`.
- **Deep / app checks (opt-in):** set `HEALTHCHECK_PATH=/` to probe end-to-end (serves
  the shared `common/index.php` through the full chain web -> php-fpm -> PHP, or
  frankenphp -> PHP), or point it at your app's own route (e.g. Laravel `/up`) to also
  validate the application. `/healthz` is independent of `SERVER_ROOT`, so mounting your
  own docroot no longer breaks the default probe (the old `/` default served your app's
  index; that caveat is gone for the default).
- **dind:** `HEALTHCHECK CMD` (shell form) runs
  `DOCKER_HOST=unix:///run/user/1000/docker.sock docker version` - healthy = the
  rootless daemon answers on its per-user socket. `start-period=30s` (rootlesskit +
  daemon are slow to come up); no PHP/curl involved.

## Compression

All three web images compress text-like responses with **brotli preferred, gzip fallback**
(one encoding per response, never double). zstd is Caddy-only: no brotli-style module exists
for Apache or Debian nginx (only Alpine nginx ships `nginx-mod-http-zstd`), so it's omitted
from nginx/apache to keep a tag's behaviour identical across OS. Not applied to `dind`.

- **frankenphp (Caddy):** the `frankenphp/Caddyfile` site block does `encode zstd br gzip`
  natively - Caddy negotiates and includes zstd here. Caddy's `minimum_length` is 512B.
- **nginx:** gzip is built in; brotli is a dynamic module (`load_module` at the top of
  `nginx.conf`, same `.so` path both distros). Packages installed per distro in the RUNTIME
  DEPS `case`: Debian `libnginx-mod-http-brotli-{filter,static}`, Alpine `nginx-mod-http-brotli`.
  The `http{}` block sets `gzip`/`brotli` on with matching `*_types` + `*_static on`; nginx
  applies only one (gzip skips a response brotli already encoded).
- **apache:** `mod_deflate` (gzip) + `mod_brotli`. Apache does **not** self-negotiate br-vs-gzip
  - `AddOutputFilterByType` with both filters double-compresses - so `vhost.conf` drives it via
  **mod_filter**: a `FilterChain COMPRESS` whose two `FilterProvider`s have mutually exclusive
  conditions (brotli when `Accept-Encoding =~ /br/`; deflate when `=~ /gzip/ && !~ /br/`, since
  browsers send `gzip, deflate, br`) and a `%{CONTENT_TYPE}` guard so images/binaries are
  skipped. Modules enabled per distro: Debian `a2enmod deflate brotli filter`; Alpine loads
  `deflate` (+guarded `brotli`) in `alpine.conf` (mod_filter is stock-loaded; the
  `apache2-brotli` package supplies mod_brotli and its `conf.d/brotli.conf` load).
- **goss:** each web `goss.yaml` has a `compression-brotli` command test - writes a 1024B
  compressible asset into `${SERVER_ROOT}` and asserts `curl -H 'Accept-Encoding: br, gzip'`
  returns `Content-Encoding: br` (catches a base-image change that drops the module).

## Per-image notes

- `fpm-nginx`, `fpm-apache`: `php:*-fpm[-alpine]` base + web server installed via
  the helper. PID 1 is s6-overlay (`ENTRYPOINT ["/init"]`, installed by
  `helper install-s6-overlay`). Services are s6-rc.d longruns under
  `<image>/s6-rc.d/` (php-fpm + the web server), COPYed into
  `/etc/s6-overlay/s6-rc.d`. The services are registered into the `user` bundle via
  empty files under `<image>/user-bundles.d/user/contents.d/` (COPYed to
  `/etc/s6-overlay/user-bundles.d`), **not** the older `s6-rc.d/user/contents.d/`:
  s6-overlay 3.2.3.1 made an in-`s6-rc.d` `user` bundle without a `type` file a fatal
  `s6-rc-compile` error (`unable to read .../user/type`) - services never start, so the
  container refuses connections while `php`/`php-fpm -tt` still work. php-fpm's run
  script uses `#!/command/with-contenv sh` so `${PHP_MEMORY_LIMIT}` still reaches it at
  runtime.
  php-fpm listens on 127.0.0.1:9000. Note: setting `ENTRYPOINT` reset the base
  image's inherited `CMD ["php-fpm"]` to empty, so /init runs only the services.
- **Startup readiness + ordering (s6, from serversideup):** the web server declares
  a `dependencies.d/php-fpm`, and php-fpm signals *readiness* (not just "started") so
  the web server only starts once FPM actually accepts connections - no startup 502
  window. Readiness is wired the s6 way: php-fpm's run is `s6-notifyoncheck -d php-fpm
  -F`, its `notification-fd` is `3`, and its `data/check` (a `php -r fsockopen` on
  :9000, no extra tooling) is polled until FPM is up. (serversideup uses their
  `php-fpm-healthcheck` binary for the same check; we don't ship it.) s6-notifyoncheck
  must run from the service dir - no `cd` before it.
- **Graceful shutdown (`STOPSIGNAL SIGTERM`):** the `php:*-fpm` base sets
  `STOPSIGNAL SIGQUIT` (php-fpm's own graceful signal, for when php-fpm is PID 1). But
  here s6-overlay is PID 1, and its scandir signal handlers wire *SIGTERM* to the
  shutdown (`.s6-svscan/SIGTERM` runs `s6-linux-init-shutdown`) while its *SIGQUIT*
  handler is empty. With the inherited SIGQUIT, `docker stop` hit the no-op handler and
  the container was SIGKILLed at the 10s timeout (exit 137). Fix: the web images
  override `STOPSIGNAL SIGTERM`, so `docker stop` triggers s6's shutdown (clean exit 0
  in ~3-4s). Each service also sets `down-signal SIGQUIT` so php-fpm/nginx/apache drain
  in-flight requests (graceful) instead of being hard-terminated; s6 then SIGKILLs any
  stragglers after `S6_KILL_GRACETIME` (3s default). Guarded by a CI "Graceful stop"
  step (fails on exit 137 / timeout). frankenphp has no s6 and stops fine on the
  default SIGTERM. (This is the opposite of serversideup's `STOPSIGNAL SIGQUIT`, which
  suits their s6 build; ours needs SIGTERM - verify with `docker inspect -f
  '{{.Config.StopSignal}}'` and the `.s6-svscan/` handlers if the base image changes.)
- **Non-root (secure by default):** the web images run unprivileged as `www-data`
  on port **8080** (`USER ${SERVER_USER}`, `EXPOSE 8080`). `SERVER_USER` is a build
  ARG (default `www-data`, persisted as ENV) used for the `chown`, `set-user-id`, and
  `USER` - unlike `SERVER_ROOT` it is *build-time only* (the `USER`/`chown` are baked
  and the container is non-root, so it cannot switch users at runtime; override with
  `--build-arg SERVER_USER=...` to rebuild, or `docker run --user` at runtime). s6-overlay has "limited"
  non-root support that works here because there are only two services and no
  fix-attrs/loggers/syslogd. Requirements: the runtime dirs must be writable by
  www-data - `chown -R www-data /run <server dirs>` (nginx: `/var/lib/nginx`
  `/var/log/nginx` which is a symlink `chown -R` won't follow; apache: switch
  `Listen 80`→`8080` and `User/Group` to www-data per distro. Each distro has an
  os-named drop-in that pulls in the shared `vhost.conf` and is inert on the other
  distro (Alpine reads `conf.d`, Debian `conf-enabled`, neither reads the other's):
  `fpm-apache/debian.conf` and `fpm-apache/alpine.conf`. Debian sets the port with a
  COPYed `fpm-apache/ports.conf` (replaces the stock `Listen 80` file wholesale, so no
  sed; modules via `a2enmod`, `User/Group` via the base envvars). Alpine's `alpine.conf`
  carries the port/user/module config, but the stock main `httpd.conf` hardcodes `Listen
  80` + a file `CustomLog` inline (both accumulate, so no include overrides them, and the
  file can't be replaced wholesale without re-listing every distro `LoadModule`) - so those
  two lines are the one remaining sed, commenting them out. Logs go to stdout/stderr so no
  log dir is chowned, see Logging). frankenphp uses
  `ENV SERVER_NAME=:8080` (plain HTTP, no
  443/auto-TLS) and chowns `/app /config /data`.
- **Host-user matching (local dev):** the web images take `USER_ID`/`GROUP_ID`
  build args; when set they `helper set-user-id www-data ...` *before* the chown,
  so www-data gets the host uid and bind-mounted files are owned correctly (matters
  on Linux; Docker Desktop auto-maps). Makefile passes them only when set (so no
  build warning on dind). Default unset = hardened uid 82/33. Runtime alternative:
  `docker run --user $(id -u):$(id -g)` (s6-overlay fixes its dir ownership on start).
- **PHP extensions - a default set, extended by deriving:** all three web images install
  the **same default extension set** with **explicit `helper` calls** in their Dockerfiles
  (no build-args, readable) - two per install manager, all needing no extra system libs:
  `install-docker-ext mysqli bcmath`, `install-pecl-ext redis-6.3.0 apcu-5.1.28`,
  `install-pie-ext php-ds/ext-ds:2.0.0 open-telemetry/ext-opentelemetry:1.3.1`
  (`install-pie-ext` installs the PIE binary itself if needed), bracketed by
  `install-build-deps $PHPIZE_DEPS unzip` / `remove-build-deps`. A `default-extensions`
  goss test asserts they load. Each image's `dev` stage does the same for xdebug/pcov/spx,
  with a `detect-os` `case` selecting per-distro `build_deps`/`runtime_deps` (Alpine
  `linux-headers zlib-dev`, Debian `zlib1g-dev`; plus a kept `unzip` for composer). The
  three base/dev blocks are identical across the images (the explicit style trades DRY for
  readability).
  - **To *extend* the defaults, derive - don't rebuild from the repo.** Dockerfile edits
    only apply when building the image from this repo; a downstream `FROM <image>:<tag>` user
    adds extensions with the baked-in `helper` (`USER root; helper install-runtime-deps
    <libs>; helper install-docker-ext/-pecl-ext/-pie-ext <ext>; USER www-data`).
    `examples/wordpress/Dockerfile` extends the defaults with one more, `gd` (+`libpng-dev`).
    PIE's ecosystem is thin - most `pecl/<name>` bridges 404 on Packagist; only a few
    (`pecl/pcov`, `pecl/zip`) and native `vendor/ext-*` install.
  - Bundled extensions (`docker-php-ext-install` / `helper install-docker-ext`) need no
    caller-provided toolchain: `docker-php-ext-install` installs its build deps transiently
    and purges them itself (verified - the Alpine build log ends with `Purging musl-dev /
    libgcc`; `gcc` is absent before and after). So `install-docker-ext` needs no
    `install-build-deps` bracket.
  - PECL/PIE compile external sources and need `$PHPIZE_DEPS` - present on Debian, absent
    on Alpine. Each web Dockerfile's `RUN` runs `helper install-build-deps $PHPIZE_DEPS unzip`
    (unzip is what PIE uses to fetch packages) around the pecl/pie installs, then
    `helper remove-build-deps` drops what was added: Alpine deletes the `apk --virtual`
    group; Debian purges only the packages it
    newly installed (base `$PHPIZE_DEPS` and runtime libs survive). So the transient build
    packages leave no trace (Debian keeps its base toolchain). Verified: pecl `redis` on
    Alpine loads and autoconf is gone afterward; pie `xdebug/xdebug` on Debian loads.
  - Extensions needing extra *system* packages get explicit `helper` calls in the
    Dockerfile (there are **no** `PHP_*_PACKAGES` build args): `install-runtime-deps`
    for libs that must stay (e.g. `gd`->`libpng-dev`, as in `examples/wordpress`), and
    the removable `install-build-deps` group for build-only headers. The `dev` stage
    does exactly this via its per-distro `detect-os` `case` (Alpine `linux-headers
    zlib-dev`, Debian `zlib1g-dev`), splitting `build_deps` (removed) from `runtime_deps`
    (kept).
  - Not expressible through the args (use the helper / a derived Dockerfile):
    `docker-php-ext-configure` flags (e.g. gd with jpeg/freetype) and per-extension PIE
    config flags (e.g. `asgrim/example-pie-extension` needs `--enable-...`).
- **Document root (`SERVER_ROOT`, runtime-overridable):** all three web images
  expose `SERVER_ROOT` (default fpm-nginx/fpm-apache `/var/www/html`, frankenphp
  `/app/public`) so the docroot can be changed with `docker run -e SERVER_ROOT=...`
  (mount your app there). Wiring differs by server: frankenphp's `Caddyfile` reads it
  natively (`root {$SERVER_ROOT:/app/public}`); Apache expands `${SERVER_ROOT}` in
  `vhost.conf` at config-parse time; nginx *cannot* expand env vars, so `nginx.conf`
  ships as `nginx.conf.template` and the nginx s6 run script renders `${SERVER_ROOT}`
  into `/run/nginx.conf` (via `sed`, only that token - `$uri`/`$document_root` are
  left intact) and starts `nginx -c /run/nginx.conf`. The shared hello-world
  `common/index.php` is COPYed into each default docroot.
- **Static files + front-controller fallback:** all three serve standard static assets
  (html/css/js/json/svg/images/fonts...) directly from `SERVER_ROOT` with correct MIME
  types - only `.php` is handed to PHP (nginx `location ~ \.php$`, Apache `<FilesMatch
  \.php$>` SetHandler, Caddy `php_server`). An **unknown path falls through to
  `index.php`** (the front-controller pattern, so framework routes work): nginx via
  `try_files $uri $uri/ /index.php?$query_string`, Caddy via `php_server`, and Apache via
  a `mod_rewrite` rule in `vhost.conf`'s `<Directory>` (`RewriteCond !-f/!-d` then
  `RewriteRule ^ index.php`). Apache's `/healthz` ProxyPass is unaffected (it claims the
  request before per-directory rewrites, so healthz stays a php-fpm ping, verified by the
  `pong` body). An app's own `public/.htaccess` still overrides (Apache `AllowOverride
  All`). A `no/such/route -> 200` goss `http` test guards the fallback in all three.
- `frankenphp`: `dunglas/frankenphp:php<ver>-bookworm|-alpine` base; serves
  `/app/public` (`SERVER_ROOT`, set in the image's own `frankenphp/Caddyfile`).
- `dind`: thin layer over `docker:*-dind-rootless` (daemon runs as the `rootless`
  user, uid 1000, via rootlesskit). Alpine-only upstream, so dind is a single
  variant (no debian/alpine split). Base entrypoint/CMD/USER inherited; run the
  container with `--privileged`. The rootless daemon socket is
  `/run/user/1000/docker.sock`, so a CLI needs `DOCKER_HOST` pointed there.
  - **Cloud CLI variants (`CLOUD` build arg):** `dind/Dockerfile` takes an optional
    `ARG CLOUD` (empty = plain dind; `aws` | `gcloud` | `azure`), branching in one
    `RUN` (as `root`, then back to `USER rootless`) to `helper install-aws-cli` /
    `install-gcloud` / `install-azure-cli`. Unknown values fail the build. Makefile
    targets `dind-aws` / `dind-gcloud` / `dind-azure` set `CLOUD` and tag
    `<docker>-rootless-<cloud>`; the base `build` macro passes `--build-arg CLOUD` when
    set (so plain `make dind` is unaffected). Tests: `make test-dind-<cloud>` runs the
    per-cloud `dind/goss.<cloud>.yaml` (via `GOSS_FILE`) = the base dind checks plus a
    `<cli> --version` probe. `ENV CLOUDSDK_PYTHON=/usr/bin/python3` is set
    unconditionally (harmless when gcloud is absent) so gcloud uses the musl python.
    Verified: all three build + run as uid 1000, and the rootless daemon still starts
    with a CLI layered on.

## Dev image variant

The three web images (`fpm-nginx`, `fpm-apache`, `frankenphp`) have a `dev` build stage
(`make <image>-dev[-<os>]`, tag `<php>-<os>-dev`) that layers a development toolbox onto
the lean prod image: **composer** + **castor** (binaries) and the **xdebug**, **pcov**,
and **spx** extensions. Not applied to `dind` (not a PHP image).

- **Structure:** multi-stage (`base`/`dev`/`prod`) - see Layout. `dev` runs as `root`
  to install, then resets `USER ${SERVER_USER}`; it inherits the prod ENTRYPOINT/
  HEALTHCHECK/etc. Building without `--target` still gives the lean image (the empty
  `prod` stage is last).
- **Extensions installed explicitly.** The `dev` stage runs `helper install-composer`,
  `install-castor`, then `install-pie-ext xdebug/xdebug:3.5.3 pecl/pcov:1.0.12
  noisebynorthwest/php-spx:0.4.22` (pinned inline, no ARGs; `install-pie-ext` installs the
  PIE binary itself if absent). pcov has no native PIE package, so it uses PIE's `pecl/`
  bridge (`pecl/pcov`); xdebug and spx have native PIE packages.
- **Per-distro packages via a `detect-os` case.** The `RUN` sets two shell vars:
  `build_deps` (removable) - `$PHPIZE_DEPS unzip` (the pecl/pie toolchain) plus the headers
  xdebug/spx compile against (Alpine `linux-headers zlib-dev`, Debian `zlib1g-dev`) - and
  `runtime_deps` (kept) - `unzip`, so runtime `composer install` can extract packages
  (Debian's base ships none; Alpine's busybox `unzip` is limited). It then calls
  `install-runtime-deps $runtime_deps`, `install-build-deps $build_deps`, the extension
  installs, and `remove-build-deps`. So the build packages leave no trace (~7 MB of headers
  saved on Alpine, plus the toolchain there); `unzip` survives because `install_build_deps`
  records for removal only what it *newly* installed (unzip was already installed as a
  runtime pkg), and on Debian the base `$PHPIZE_DEPS` stays (its own). Each `dev` stage is
  self-contained - `docker build --target dev` works without the Makefile. Verified on both
  distros: extensions load, headers gone (runtime
  `zlib`/`zlib1g` stays), `unzip` present.
- **Config (`common/dev.ini` -> `conf.d/zz-dev.ini`)** tunes the three extensions,
  env-overridable like the shared php.ini. **xdebug is off by default**
  (`xdebug.mode = ${XDEBUG_MODE:-off}`) so the dev image carries zero xdebug overhead
  until opted in (`-e XDEBUG_MODE=debug,coverage`; xdebug also reads `XDEBUG_MODE`
  natively). `pcov.enabled` defaults on (idle until a runner collects; don't drive
  coverage with both pcov and xdebug). spx is dormant until activated; its HTTP UI is
  gated by `spx.http_key` + `spx.http_ip_whitelist` (keep tight before exposing).
- **Tests:** `make test-dev[-<image>]` runs each image's own `<image>/goss.dev.yaml` (via
  `GOSS_FILE`, selecting it over the prod `<image>/goss.yaml`) against the Alpine `-dev`
  tag - asserts the 5 tools are present, xdebug loads but defaults `off`, and
  `XDEBUG_MODE` overrides it. The three files are currently identical (a dev-toolbox
  smoke test); keep them in sync, or diverge per image as needed.

## Status

Building and runtime-tested (goss): all images. (Previously-known gap - `fpm-apache`
on Alpine serving `.php` as source - is **closed**: the Alpine build now installs the
`apache2-proxy` package, so mod_proxy_fcgi executes `.php` like Debian.)
