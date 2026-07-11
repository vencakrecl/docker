# Local Docker image builds.
#
# Each image has a single Dockerfile that receives its base image via the
# BASE_IMAGE build arg; common/helper abstracts apt vs apk (and more) so the
# same Dockerfile works for Debian and Alpine bases.
#
# The build context is the repo root (note the trailing `.` and `-f <image>/Dockerfile`)
# so every Dockerfile can COPY the shared common/helper.
#
# Local builds target the host platform only: `docker buildx build --load` cannot
# load a multi-platform manifest into the engine. Multi-arch (amd64+arm64) images
# are produced at push time. See https://docs.docker.com/build/building/multi-platform/

PHP_VERSION    ?= 8.4
DOCKER_VERSION ?= 29
REGISTRY       ?=
PLATFORM       ?=

# Output/cache control. Default `--load` builds a single (host) arch into the local
# engine for testing. To build+push a multi-arch manifest (CI push job):
#   make fpm-nginx-alpine REGISTRY=ghcr.io/owner/ OUTPUT=--push PLATFORM=linux/amd64,linux/arm64
# CACHE lets CI pass buildx cache flags (e.g. --cache-from/--cache-to type=gha).
OUTPUT ?= --load
CACHE  ?=

# For local development: set USER_ID/GROUP_ID to match your host user so
# bind-mounted files get the right owner (Linux hosts). Only passed when set.
#   make fpm-nginx-alpine USER_ID=$(id -u) GROUP_ID=$(id -g)
USER_ID  ?=
GROUP_ID ?=

# $(call build,<image>,<base-image>,<tag>)
BUILDX = docker buildx build $(OUTPUT) $(CACHE) $(if $(PLATFORM),--platform $(PLATFORM))
define build
	$(BUILDX) \
	  --build-arg BASE_IMAGE=$(2) \
	  $(if $(USER_ID),--build-arg USER_ID=$(USER_ID)) \
	  $(if $(GROUP_ID),--build-arg GROUP_ID=$(GROUP_ID)) \
	  -t $(REGISTRY)$(1):$(3) \
	  -f $(1)/Dockerfile .
endef

.PHONY: build
build: fpm-nginx fpm-apache frankenphp dind ## Build every image (both OS variants)

# --- fpm-nginx ---------------------------------------------------------------
.PHONY: fpm-nginx fpm-nginx-debian fpm-nginx-alpine
fpm-nginx: fpm-nginx-debian fpm-nginx-alpine
fpm-nginx-debian:
	$(call build,fpm-nginx,php:$(PHP_VERSION)-fpm,$(PHP_VERSION)-debian)
fpm-nginx-alpine:
	$(call build,fpm-nginx,php:$(PHP_VERSION)-fpm-alpine,$(PHP_VERSION)-alpine)

# --- fpm-apache --------------------------------------------------------------
.PHONY: fpm-apache fpm-apache-debian fpm-apache-alpine
fpm-apache: fpm-apache-debian fpm-apache-alpine
fpm-apache-debian:
	$(call build,fpm-apache,php:$(PHP_VERSION)-fpm,$(PHP_VERSION)-debian)
fpm-apache-alpine:
	$(call build,fpm-apache,php:$(PHP_VERSION)-fpm-alpine,$(PHP_VERSION)-alpine)

# --- frankenphp --------------------------------------------------------------
.PHONY: frankenphp frankenphp-debian frankenphp-alpine
frankenphp: frankenphp-debian frankenphp-alpine
frankenphp-debian:
	$(call build,frankenphp,dunglas/frankenphp:php$(PHP_VERSION)-bookworm,$(PHP_VERSION)-debian)
frankenphp-alpine:
	$(call build,frankenphp,dunglas/frankenphp:php$(PHP_VERSION)-alpine,$(PHP_VERSION)-alpine)

# --- dind --------------------------------------------------------------------
# Rootless dind is Alpine-only upstream, so dind is a single variant. The tag is
# `-rootless` (not an OS): the meaningful trait is that the daemon runs rootless.
.PHONY: dind
dind:
	$(call build,dind,docker:$(DOCKER_VERSION)-dind-rootless,$(DOCKER_VERSION)-rootless)

# --- tests -------------------------------------------------------------------
# Runtime tests: each image is started and probed with goss (via dgoss) using the
# <image>/goss.yaml in its directory. Tests the Alpine variant.
# Requires goss + dgoss on PATH: https://github.com/goss-org/goss/tree/master/extras/dgoss
GOSS_SLEEP ?= 6
DGOSS = command -v dgoss >/dev/null 2>&1 || { echo "dgoss not on PATH - install goss + dgoss (extras/dgoss in goss-org/goss)"; exit 1; }; \
	GOSS_SLEEP=$(GOSS_SLEEP) dgoss run

.PHONY: test
test: test-fpm-nginx test-fpm-apache test-frankenphp test-dind ## Runtime-test every image (Alpine, needs goss + dgoss)

.PHONY: test-fpm-nginx
test-fpm-nginx: fpm-nginx-alpine
	cd fpm-nginx && $(DGOSS) $(REGISTRY)fpm-nginx:$(PHP_VERSION)-alpine

.PHONY: test-fpm-apache
test-fpm-apache: fpm-apache-alpine
	cd fpm-apache && $(DGOSS) $(REGISTRY)fpm-apache:$(PHP_VERSION)-alpine

.PHONY: test-frankenphp
test-frankenphp: frankenphp-alpine
	cd frankenphp && $(DGOSS) $(REGISTRY)frankenphp:$(PHP_VERSION)-alpine

.PHONY: test-dind
test-dind: GOSS_SLEEP = 15   # rootless dind (rootlesskit + network) needs longer to be ready
test-dind: dind
	cd dind && $(DGOSS) --privileged $(REGISTRY)dind:$(DOCKER_VERSION)-rootless

# --- examples ----------------------------------------------------------------
# Install a framework skeleton into examples/<fw>/app for local testing with the
# per-framework docker-compose.yml. Only the compose files are committed; the app is
# git-ignored. Installs run in a throwaway container (no host PHP/Composer needed).
#   make example-symfony && docker compose -f examples/symfony/docker-compose.yml up --build
COMPOSER_IMAGE ?= composer:2
# $(call composer_create,<package>,<framework-dir>)
define composer_create
	docker run --rm -v "$(CURDIR)/examples/$(2)/app:/app" -w /app $(COMPOSER_IMAGE) \
	  composer create-project $(1) . --no-interaction
endef

.PHONY: example-laravel
example-laravel: ## Install a Laravel skeleton into examples/laravel/app
	$(call composer_create,laravel/laravel,laravel)

.PHONY: example-symfony
example-symfony: ## Install a Symfony skeleton into examples/symfony/app
	$(call composer_create,symfony/skeleton,symfony)

.PHONY: example-nette
example-nette: ## Install a Nette skeleton into examples/nette/app
	$(call composer_create,nette/web-project,nette)

.PHONY: example-wordpress
example-wordpress: ## Download WordPress core into examples/wordpress/app
	docker run --rm -v "$(CURDIR)/examples/wordpress/app:/app" -w /app alpine \
	  sh -c 'wget -qO- https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1 -C /app'

.PHONY: help
help: ## List the available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  %-22s %s\n", $$1, $$2}'
