[← Back to README](../README.md)

# Configuration

Everything is env-driven. The shared `common/php.ini` and `common/php-fpm.conf`
use PHP's `${VAR:-default}` expansion (evaluated at parse time), so every setting
carries its default in the file and is overridable at runtime with no rebuild:

```sh
docker run -e PHP_MEMORY_LIMIT=512M ...   # memory_limit = 512M (default 128M)
```

To add a knob, add a `key = ${ENV_VAR:-default}` line to the relevant file - no
Dockerfile change needed.

## PHP (`php.ini`)

Copied to `$PHP_INI_DIR/conf.d/zz-common.ini` on all three web images. Error-logging
knobs (`log_errors`, `display_errors`, …) are listed under [Logging](#logging).

| Env var | Directive | Default |
|---------|-----------|---------|
| `PHP_MEMORY_LIMIT` | `memory_limit` | `128M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `upload_max_filesize` | `2M` |
| `PHP_POST_MAX_SIZE` | `post_max_size` | `8M` |
| `PHP_MAX_INPUT_VARS` | `max_input_vars` | `1000` |
| `PHP_DATE_TIMEZONE` | `date.timezone` | `UTC` |
| `PHP_OPCACHE_MEMORY_CONSUMPTION` | `opcache.memory_consumption` | `128` |
| `PHP_OPCACHE_MAX_ACCELERATED_FILES` | `opcache.max_accelerated_files` | `10000` |
| `PHP_OPCACHE_INTERNED_STRINGS_BUFFER` | `opcache.interned_strings_buffer` | `8` |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `opcache.validate_timestamps` | `1` (set `0` in prod, reset OPcache on deploy) |
| `PHP_OPCACHE_ENABLE_CLI` | `opcache.enable_cli` | `0` |
| `PHP_OPCACHE_PRELOAD` | `opcache.preload` | *(empty = off)* |
| `PHP_OPCACHE_PRELOAD_USER` | `opcache.preload_user` | `www-data` |
| `PHP_REALPATH_CACHE_SIZE` | `realpath_cache_size` | `4096K` |
| `PHP_REALPATH_CACHE_TTL` | `realpath_cache_ttl` | `120` |

`max_execution_time` is not a separate knob - it tracks `SERVER_TIMEOUT` (see
[Server & runtime](#server--runtime)) so PHP's limit and the web-server backend
timeout stay aligned.

## PHP-FPM (`php-fpm.conf`)

The fpm images (`fpm-nginx`, `fpm-apache`) also copy `common/php-fpm.conf` into
`/usr/local/etc/php-fpm.d/zzz-common.conf` for process-manager tuning. frankenphp
embeds PHP (no php-fpm), so it ignores these.

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

## Server & runtime

Image `ENV`s that control the docroot, timeouts and health probe. All are
runtime-overridable **except** `SERVER_USER`, which is a build-time `ARG` (the
`USER`/`chown` are baked in) - override it with `--build-arg SERVER_USER=...`.

| Env var | Purpose | Default |
|---------|---------|---------|
| `SERVER_ROOT` | document root | `/var/www/html` (fpm), `/app/public` (frankenphp) |
| `SERVER_TIMEOUT` | request time budget: PHP `max_execution_time` **and** the web-server backend timeout (positive integer of seconds; fpm images reject `0`) | `30` |
| `SERVER_USER` | run-as user (build-time only) | `www-data` |
| `SERVER_NAME` | Caddy listener (frankenphp only) | `:8080` |
| `HEALTHCHECK_PATH` | path the `HEALTHCHECK` probes; set `/` for an end-to-end check | `/healthz` |
| `HEALTHCHECK_PORT` | port the `HEALTHCHECK` probes | `8080` |
| `CADDY_SERVER_EXTRA_DIRECTIVES` | extra Caddy site-block directives (frankenphp only) | `respond /healthz 200` |

## Logging

All images write logs to the container's **stdout/stderr**, so `docker logs` shows
everything - no log files inside the container, nothing to mount or rotate.

| Source | Destination |
|--------|-------------|
| PHP engine errors (all web images) | stderr |
| php-fpm master + worker output (`fpm-nginx`, `fpm-apache`) | stderr (base image default; workers folded in via `catch_workers_output`) |
| php-fpm access log | stderr |
| nginx access / error (`fpm-nginx`) | stdout / stderr |
| Apache access / error (`fpm-apache`) | stdout / stderr |
| Caddy runtime / error (`frankenphp`) | stderr |
| dockerd (`dind`) | stderr (base image default) |

PHP error logging (`common/php.ini`):

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

## Dev image (`xdebug` / `pcov` / `spx`)

Only in the `-dev` image variant (tag `<php>-<os>-dev`), which layers the dev toolbox
onto the lean image. `common/dev.ini` tunes the three dev extensions; env-overridable
like the shared php.ini. xdebug is **off** by default (zero overhead until opted in).

| Env var | Directive | Default |
|---------|-----------|---------|
| `XDEBUG_MODE` | `xdebug.mode` | `off` |
| `XDEBUG_CLIENT_HOST` | `xdebug.client_host` | `host.docker.internal` |
| `XDEBUG_START_WITH_REQUEST` | `xdebug.start_with_request` | `yes` |
| `PCOV_ENABLED` | `pcov.enabled` | `1` |
| `SPX_DATA_DIR` | `spx.data_dir` | `/tmp/spx` |
| `SPX_HTTP_ENABLED` | `spx.http_enabled` | `1` |
| `SPX_HTTP_KEY` | `spx.http_key` | `dev` |
| `SPX_HTTP_IP_WHITELIST` | `spx.http_ip_whitelist` | `127.0.0.1` |

Enable xdebug per run, e.g. `-e XDEBUG_MODE=debug,coverage`. Don't drive coverage with
both pcov and xdebug at once. Tighten `SPX_HTTP_KEY` / `SPX_HTTP_IP_WHITELIST` before
exposing the SPX web UI. (xdebug and SPX also honour their own native env vars -
`XDEBUG_MODE`, `SPX_ENABLED=1` for CLI profiling.)
