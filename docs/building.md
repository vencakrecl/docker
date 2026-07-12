[← Back to README](../README.md)

# Building & local development

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
[`docker-compose.example.yml`](../docker-compose.example.yml). Run it:

```sh
USER_ID=$(id -u) GROUP_ID=$(id -g) \
  docker compose -f docker-compose.example.yml up --build
```
