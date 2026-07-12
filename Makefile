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

# $(call build,<image>,<base-image>,<tag>[,<target>])
# The optional 4th arg selects a Dockerfile stage (--target); omitted = the default
# (last) stage, which is the lean prod image. The dev targets pass `dev`.
BUILDX = docker buildx build $(OUTPUT) $(CACHE) $(if $(PLATFORM),--platform $(PLATFORM))
define build
	$(BUILDX) \
	  --build-arg BASE_IMAGE=$(2) \
	  $(if $(4),--target $(4)) \
	  $(if $(CLOUD),--build-arg CLOUD=$(CLOUD)) \
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

# --- dev variants ------------------------------------------------------------
# Each web image's Dockerfile has a `dev` stage (--target dev) that layers the dev
# toolbox onto the lean image: composer, castor, and the xdebug/pcov/spx extensions.
# The extension list + its distro-specific build headers are defined in the Dockerfile's
# `dev` stage (explicit `helper install-*-ext` calls; xdebug off by default, see
# common/dev.ini), so these targets just select the stage. Tag: <php>-<os>-dev.
.PHONY: dev
dev: fpm-nginx-dev fpm-apache-dev frankenphp-dev ## Build the dev variants of the web images (both OS)

.PHONY: fpm-nginx-dev fpm-nginx-dev-debian fpm-nginx-dev-alpine
fpm-nginx-dev: fpm-nginx-dev-debian fpm-nginx-dev-alpine
fpm-nginx-dev-debian:
	$(call build,fpm-nginx,php:$(PHP_VERSION)-fpm,$(PHP_VERSION)-debian-dev,dev)
fpm-nginx-dev-alpine:
	$(call build,fpm-nginx,php:$(PHP_VERSION)-fpm-alpine,$(PHP_VERSION)-alpine-dev,dev)

.PHONY: fpm-apache-dev fpm-apache-dev-debian fpm-apache-dev-alpine
fpm-apache-dev: fpm-apache-dev-debian fpm-apache-dev-alpine
fpm-apache-dev-debian:
	$(call build,fpm-apache,php:$(PHP_VERSION)-fpm,$(PHP_VERSION)-debian-dev,dev)
fpm-apache-dev-alpine:
	$(call build,fpm-apache,php:$(PHP_VERSION)-fpm-alpine,$(PHP_VERSION)-alpine-dev,dev)

.PHONY: frankenphp-dev frankenphp-dev-debian frankenphp-dev-alpine
frankenphp-dev: frankenphp-dev-debian frankenphp-dev-alpine
frankenphp-dev-debian:
	$(call build,frankenphp,dunglas/frankenphp:php$(PHP_VERSION)-bookworm,$(PHP_VERSION)-debian-dev,dev)
frankenphp-dev-alpine:
	$(call build,frankenphp,dunglas/frankenphp:php$(PHP_VERSION)-alpine,$(PHP_VERSION)-alpine-dev,dev)

# --- dind --------------------------------------------------------------------
# Rootless dind is Alpine-only upstream, so dind is a single variant. The tag is
# `-rootless` (not an OS): the meaningful trait is that the daemon runs rootless.
.PHONY: dind
dind:
	$(call build,dind,docker:$(DOCKER_VERSION)-dind-rootless,$(DOCKER_VERSION)-rootless)

# Cloud CLI variants: same dind image + one cloud CLI, selected by the CLOUD build
# arg (see dind/Dockerfile). Tag suffix names the trait, like -rootless does:
# <docker>-rootless-<cloud>. Alpine only (the dind base is Alpine).
.PHONY: dind-aws dind-gcloud dind-azure
dind-aws: CLOUD = aws
dind-aws:
	$(call build,dind,docker:$(DOCKER_VERSION)-dind-rootless,$(DOCKER_VERSION)-rootless-aws)
dind-gcloud: CLOUD = gcloud
dind-gcloud:
	$(call build,dind,docker:$(DOCKER_VERSION)-dind-rootless,$(DOCKER_VERSION)-rootless-gcloud)
dind-azure: CLOUD = azure
dind-azure:
	$(call build,dind,docker:$(DOCKER_VERSION)-dind-rootless,$(DOCKER_VERSION)-rootless-azure)

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

# Cloud-variant tests: the base dind checks plus a "<cli> --version" probe, via each
# image's goss.<cloud>.yaml (GOSS_FILE) instead of the prod goss.yaml.
.PHONY: test-dind-aws test-dind-gcloud test-dind-azure
test-dind-aws test-dind-gcloud test-dind-azure: GOSS_SLEEP = 15
test-dind-aws: export GOSS_FILE = goss.aws.yaml
test-dind-aws: dind-aws
	cd dind && $(DGOSS) --privileged $(REGISTRY)dind:$(DOCKER_VERSION)-rootless-aws
test-dind-gcloud: export GOSS_FILE = goss.gcloud.yaml
test-dind-gcloud: dind-gcloud
	cd dind && $(DGOSS) --privileged $(REGISTRY)dind:$(DOCKER_VERSION)-rootless-gcloud
test-dind-azure: export GOSS_FILE = goss.azure.yaml
test-dind-azure: dind-azure
	cd dind && $(DGOSS) --privileged $(REGISTRY)dind:$(DOCKER_VERSION)-rootless-azure

# Dev-variant smoke tests: assert the dev toolbox (composer, castor, xdebug, pcov, spx)
# is present, using each image's <image>/goss.dev.yaml (GOSS_FILE) instead of its
# prod <image>/goss.yaml. Runs the Alpine -dev tag.
.PHONY: test-dev
test-dev: test-dev-fpm-nginx test-dev-fpm-apache test-dev-frankenphp ## Runtime-test the dev variants (Alpine)

.PHONY: test-dev-fpm-nginx
test-dev-fpm-nginx: export GOSS_FILE = goss.dev.yaml
test-dev-fpm-nginx: fpm-nginx-dev-alpine
	cd fpm-nginx && $(DGOSS) $(REGISTRY)fpm-nginx:$(PHP_VERSION)-alpine-dev

.PHONY: test-dev-fpm-apache
test-dev-fpm-apache: export GOSS_FILE = goss.dev.yaml
test-dev-fpm-apache: fpm-apache-dev-alpine
	cd fpm-apache && $(DGOSS) $(REGISTRY)fpm-apache:$(PHP_VERSION)-alpine-dev

.PHONY: test-dev-frankenphp
test-dev-frankenphp: export GOSS_FILE = goss.dev.yaml
test-dev-frankenphp: frankenphp-dev-alpine
	cd frankenphp && $(DGOSS) $(REGISTRY)frankenphp:$(PHP_VERSION)-alpine-dev

.PHONY: help
help: ## List the available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  %-22s %s\n", $$1, $$2}'
