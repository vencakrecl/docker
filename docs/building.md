[← Back to README](../README.md)

# Building & local development

## Layout

```
Makefile              # local build targets
common/bin/           # shared build toolbox: one jarvis-* command per task
common/php.ini        # shared PHP config, copied into conf.d on PHP images
common/php-fpm.conf   # shared PHP-FPM pool tuning, for the fpm images
<image>/Dockerfile    # one Dockerfile per image; base image via BASE_IMAGE arg
<image>/goss.yaml     # runtime tests for the image (dgoss)
```

Every image has a single Dockerfile. The Debian/Alpine difference is handled at
build time: the base image comes from the `BASE_IMAGE` build arg (via the Makefile),
and the `common/bin/jarvis-*` commands abstract the distro. The build context is the
repo root, and each Dockerfile does `COPY common/bin/ /usr/local/bin/` so every
command is on `PATH`.

Each command is a standalone script named `jarvis-<command>`:

| Command | Purpose |
|---------|---------|
| `jarvis-detect-arch` / `jarvis-detect-os` | canonical arch (`amd64`/`arm64`) and distro (`debian`/`alpine`) |
| `jarvis-set-user-id <user> <uid> [gid]` | change a user's uid/gid (host-user matching) |
| `jarvis-verify-sha256 <file> <sha256>` | fail unless the file's sha256 matches |
| `jarvis-install-runtime-deps <pkgs...>` | apt-get or apk, with cache cleanup |
| `jarvis-install-s6-overlay` | s6-overlay init/process supervisor |
| `jarvis-install-composer` | Composer (sha256-verified) |
| `jarvis-install-pie` | PIE, the PHP extension installer |
| `jarvis-install-castor` | Castor task runner (static binary) |
| `jarvis-install-build-deps <pkgs...>` / `jarvis-remove-build-deps` | install the pecl/pie toolchain as a removable group, then drop what was added |
| `jarvis-install-docker-ext <ext...>` | first choice for extensions bundled with PHP |
| `jarvis-install-pie-ext <ext...>` | install + enable external PHP extensions via PIE |
| `jarvis-install-pecl-ext <ext...>` | legacy fallback when PIE cannot provide the extension/version |
| `jarvis-install-aws-cli` / `jarvis-install-gcloud` / `jarvis-install-azure-cli` | cloud CLI for the `dind` variants (Alpine only) |

On Debian, `jarvis-install-runtime-deps` also accepts native
[APT package-name patterns](https://manpages.debian.org/bookworm/apt/apt-patterns.7.en.html).
The web images declare ICU, ZIP, and PNG runtime libraries in `runtime_deps` using
anchored patterns, so ABI suffixes can vary with the Debian release without also
matching development packages. They are installed explicitly before build dependencies,
which keeps them through `apt-get purge --auto-remove`. PNG's pattern also accepts
the `t64` suffix and excludes virtual package names such as `libpng12-0`.
Quote patterns passed directly to the command; use `set -f` before expanding a
whitespace-separated package list to disable shell filename expansion.

Production and dev Dockerfiles pass extension package names to PIE without version
pins, so PIE resolves compatible releases at build time. `igbinary/igbinary:@RC`
allows release candidates because PIE currently has no compatible stable release.

Prefer `jarvis-install-docker-ext` → `jarvis-install-pie-ext` →
`jarvis-install-pecl-ext`. The current images use bundled PHP source and PIE only;
keep PECL for unsupported external packages. A PIE package named `pecl/pcov` uses
PIE, despite its namespace.

Pass configure flags as part of a quoted extension argument:

```sh
jarvis-install-docker-ext mysqli intl zip "gd --with-freetype --with-jpeg --with-webp"
```

The installer configures extensions that have flags, then installs the full list
in one call. Each specification is split on whitespace; use `--option=value`
without spaces in the value. GD needs these flags to enable FreeType, JPEG, and
WebP support; installing their libraries alone does not enable those features.

Tool versions/digests are pinned at the top of each installer that owns them:
`S6_OVERLAY_*` in `jarvis-install-s6-overlay`, `COMPOSER_*` in `jarvis-install-composer`,
`PIE_*` in `jarvis-install-pie`, `CASTOR_*` in `jarvis-install-castor`, `GCLOUD_*` in
`jarvis-install-gcloud` (AWS CLI tracks the Alpine repo; azure-cli's version lives in
`dind/azure-cli-requirements.txt`). Edit the pin in its file to change a version; they
read from the environment, so a Dockerfile can also declare a matching `ARG` and pass
it through for per-build overrides.

## Building locally

```sh
make build              # all images, both OS variants
make fpm-nginx          # one image, both variants
make fpm-nginx-alpine   # one image, one variant
make dind               # plain rootless dind
make dind-aws           # dind + AWS CLI (also dind-gcloud, dind-azure)
make help               # list targets
```

Overridable variables: `PHP_VERSION` (default 8.5), `DOCKER_VERSION` (default 29,
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
[`docker-compose.example.yml`](../docker-compose.example.yml). Run it:

```sh
USER_ID=$(id -u) GROUP_ID=$(id -g) \
  docker compose -f docker-compose.example.yml up --build
```
