# Examples: run real framework apps on the web images

Symfony, Laravel, and Nette run on all three web images (`fpm-nginx`, `fpm-apache`,
`frankenphp`) at once, built straight from the repo, so you can smoke-test the images
against a real front controller: docroot via `SERVER_ROOT`, routing, the built-in
`HEALTHCHECK`, and graceful `docker stop`. **WordPress is different**: it runs only on
`fpm-nginx` and is built by **deriving** from that image (`wordpress/Dockerfile`) to show
how to add extensions when you consume an image as a base (see below).

Only the `docker-compose.yml` files (and `wordpress/Dockerfile`) are committed. The
framework skeleton is installed on demand into `<framework>/app/` (git-ignored) by a
`make` target.

Each compose tunes PHP for its framework through the images' **env knobs**
(`common/php.ini` - e.g. `PHP_OPCACHE_MEMORY_CONSUMPTION`, `PHP_MEMORY_LIMIT`,
`PHP_UPLOAD_MAX_FILESIZE`), set under `environment:` - not a mounted `php.ini`. The
values follow each framework's documented recommendations (OPcache sizing for
Symfony/Laravel/Nette from Symfony's performance docs + the PHP manual; upload/memory
limits for WordPress). `opcache.validate_timestamps` is left on (dev) so edits show up;
set `PHP_OPCACHE_VALIDATE_TIMESTAMPS=0` in production.

## Layout

```
examples/
  laravel/docker-compose.yml      # SERVER_ROOT=/app/public
  symfony/docker-compose.yml      # SERVER_ROOT=/app/public
  nette/docker-compose.yml        # SERVER_ROOT=/app/www
  wordpress/docker-compose.yml    # SERVER_ROOT=/app  (+ a MariaDB service)
```

## Use

From the repo root: install the skeleton, then bring the stack up.

```sh
make -C examples symfony                                        # -> examples/symfony/app
docker compose -f examples/symfony/docker-compose.yml up --build -d
curl localhost:8081/     # fpm-nginx
curl localhost:8082/     # fpm-apache
curl localhost:8083/     # frankenphp
docker compose -f examples/symfony/docker-compose.yml ps    # HEALTHCHECK status
docker compose -f examples/symfony/docker-compose.yml down
```

Targets: `make -C examples laravel`, `make -C examples symfony`, `make -C examples nette`,
`make -C examples wordpress`. Each installs into `<framework>/app` via a throwaway
container (no host PHP/Composer needed). Symfony/Laravel/Nette use ports 8081/8082/8083
(one per image); WordPress uses only 8081 (`fpm-nginx`). Run one framework at a time.

## Adding PHP extensions (WordPress shows the pattern)

The images ship a default extension set (`mysqli bcmath redis apcu ext-ds
ext-opentelemetry`) on top of the stock `php:*-fpm` extensions. When an app needs more,
the intended way is to **derive from the image** and add them with the baked-in
`jarvis-*` commands - no repo build context, no build-args, no rebuilding the base from
source. **WordPress demonstrates this**: `wordpress/Dockerfile` is `FROM fpm-nginx:<tag>`
+ `jarvis-install-docker-ext gd` (mysqli is already a base default; see the root
README/CLAUDE.md for the `jarvis-*` commands). Build the base first
(`make fpm-nginx-alpine`), then `docker compose -f examples/wordpress/docker-compose.yml up
--build`.

| Framework | Extensions beyond the base | Notes |
| --------- | -------------------------- | ----- |
| Symfony (skeleton) | none (uses polyfills) | works out of the box |
| Nette (web-project) | none for the welcome page | |
| Laravel | usually `pdo_*`, `mbstring` is bundled | fine for the welcome page; a DB app needs `pdo_mysql`/`pdo_pgsql` |
| WordPress | `gd` (+ a DB; `mysqli` is a base default) | `gd` added by deriving (see `wordpress/Dockerfile`); a fresh core redirects to the installer until these are present |

Symfony/Laravel/Nette build the images straight from the repo for a quick smoke test;
WordPress is the one that shows consuming an image **as a base** and extending it.

## Health status

The images' `HEALTHCHECK` defaults to `HEALTHCHECK_PATH=/healthz` - php-fpm's ping (fpm
images) or a Caddy static 200 (frankenphp), answered without running app code. So **all
four examples report `healthy` out of the box**, independent of the app's own routes
(this is why a bare Symfony skeleton no longer shows `unhealthy` - the old `/` default
hit its route-less 404). `/healthz` only proves the web server + PHP runtime are up, not
that the app works; override `HEALTHCHECK_PATH` for a deeper, app-level check:

| App | Deeper check | Behaviour |
| --- | ------------ | --------- |
| Laravel | `HEALTHCHECK_PATH=/up` (set in its compose) | built-in health route, 200 if the app boots (dispatches `DiagnosingHealth` for DB/cache checks) - validates the app, not just the runtime |
| Symfony | add a route, then set `HEALTHCHECK_PATH` to it | no built-in health route (unlike Laravel's `/up`) |
| Nette | `HEALTHCHECK_PATH=/` | welcome page returns 200 |
| WordPress | `HEALTHCHECK_PATH=/` | fresh core 302→installer; healthy via 3xx (`curl -L`) |

Set `HEALTHCHECK_PATH=/` to serve the docroot's `index.php` end-to-end, or any 2xx/3xx
app route.

## Ownership / writes

Apps are mounted read-write (frameworks write caches/logs). On Docker Desktop (macOS)
this works out of the box. On Linux, the container's `www-data` (uid 82) can't write
host-owned files - build the image with `USER_ID`/`GROUP_ID`, or add `user:` to the
service, to match your uid.
