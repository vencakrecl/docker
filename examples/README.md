# Examples: run real framework apps on the web images

Each subfolder runs a real PHP framework on all three web images (`fpm-nginx`,
`fpm-apache`, `frankenphp`) at once, so you can smoke-test the images against a real
front controller: docroot via `SERVER_ROOT`, routing, the built-in `HEALTHCHECK`, and
graceful `docker stop`.

Only the `docker-compose.yml` files are committed. The framework skeleton is installed
on demand into `<framework>/app/` (git-ignored) by a `make` target.

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
make example-symfony                                        # -> examples/symfony/app
docker compose -f examples/symfony/docker-compose.yml up --build -d
curl localhost:8081/     # fpm-nginx
curl localhost:8082/     # fpm-apache
curl localhost:8083/     # frankenphp
docker compose -f examples/symfony/docker-compose.yml ps    # HEALTHCHECK status
docker compose -f examples/symfony/docker-compose.yml down
```

Targets: `make example-laravel`, `make example-symfony`, `make example-nette`,
`make example-wordpress`. Each installs into `<framework>/app` via a throwaway
container (no host PHP/Composer needed). All four composes use ports 8081/8082/8083,
so run one framework at a time.

## Required PHP extensions (heads-up)

The images ship the stock `php:*-fpm` extension set. Some frameworks need more, added
per image with `helper install-docker-ext <ext>` (see the root README/CLAUDE.md):

| Framework | Extensions beyond the base | Notes |
| --------- | -------------------------- | ----- |
| Symfony (skeleton) | none (uses polyfills) | works out of the box |
| Nette (web-project) | none for the welcome page | |
| Laravel | usually `pdo_*`, `mbstring` is bundled | fine for the welcome page; a DB app needs `pdo_mysql`/`pdo_pgsql` |
| WordPress | `mysqli`, `gd` (+ a DB) | a fresh core redirects to the installer until these are added |

These examples are the place to discover exactly which extensions a real app needs on
these base images.

## Health status

The images' `HEALTHCHECK` probes `/` (`HEALTHCHECK_PATH=/`). A bare skeleton may not
return 2xx there - e.g. a fresh Symfony skeleton serves its "Welcome" page with a **404**
(no routes yet), so the container shows `unhealthy` even though the stack works. Add a
route (or a real app), or override `HEALTHCHECK_PATH` to a 2xx route, to get `healthy`.
Laravel's and Nette's default homepages return 200.

## Ownership / writes

Apps are mounted read-write (frameworks write caches/logs). On Docker Desktop (macOS)
this works out of the box. On Linux, the container's `www-data` (uid 82) can't write
host-owned files - build the image with `USER_ID`/`GROUP_ID`, or add `user:` to the
service, to match your uid.
