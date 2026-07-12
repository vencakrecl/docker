[← Back to README](../README.md)

# Testing & CI

## Testing

Tests run against a **running** container with
[dgoss](https://github.com/goss-org/goss/tree/master/extras/dgoss): each target
starts the image and checks the `<image>/goss.yaml` in that image's directory.

```sh
make test           # runtime-test every image (Alpine)
make test-fpm-nginx # one image
make test-dind      # plain rootless dind (--privileged)
make test-dind-aws  # dind + AWS CLI (also test-dind-gcloud, test-dind-azure)
```

Requires `goss` + `dgoss` on `PATH`. Each image's checks live in its
`<image>/goss.yaml`; the `dind` cloud variants use `<image>/goss.<cloud>.yaml`
(selected via `GOSS_FILE`), which add a `<cli> --version` probe to the base checks.

## CI

CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) runs on push/PR as a
**matrix**: one parallel job per image × PHP version × arch (`amd64` + `arm64`) × OS
(`alpine` + `debian`), each building and goss-testing that one variant; `dind` is a
separate per-arch job. The PHP version set is per image - a `matrix` job emits it as
JSON so build and push share one list.

On push to **main**, each job's third step pushes the **tested** image to **GHCR**
under a per-arch tag; the `release-php-image`/`release-dind-image` jobs then assemble the
**multi-arch** (amd64+arm64) manifest (`ghcr.io/<owner>/<image>:<tag>`) with
`docker buildx imagetools create`. No QEMU - the published images are exactly the
ones built and goss-tested natively on each arch.

If the repo variable `DOCKERHUB_USERNAME` and secret `DOCKERHUB_TOKEN` are configured,
the same steps also mirror to **Docker Hub** (`docker.io/<DOCKERHUB_USERNAME>/<image>:<tag>`);
the Docker Hub steps are skipped when the variable is unset, so CI stays green without them.

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
  Debian/rootless upstream, so dind is a single variant). Optional cloud CLI variants
  (`-aws`, `-gcloud`, `-azure`) add one provider's CLI via the `CLOUD` build arg.
