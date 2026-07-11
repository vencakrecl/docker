# Install the framework example apps for local testing with the per-framework
# docker-compose.yml files. Run from the repo root (make -C examples <target>) or
# from here (make <target>). Only the compose files are committed; each skeleton is
# installed into <framework>/app (git-ignored) via a throwaway container - no host
# PHP/Composer needed. Then, from the repo root:
#   docker compose -f examples/<framework>/docker-compose.yml up --build

COMPOSER_IMAGE ?= composer:2

# $(call composer_create,<package>,<framework-dir>)
define composer_create
	docker run --rm -v "$(CURDIR)/$(2)/app:/app" -w /app $(COMPOSER_IMAGE) \
	  composer create-project $(1) . --no-interaction
endef

.PHONY: laravel
laravel: ## Install a Laravel skeleton into laravel/app
	$(call composer_create,laravel/laravel,laravel)

.PHONY: symfony
symfony: ## Install a Symfony skeleton into symfony/app
	$(call composer_create,symfony/skeleton,symfony)

.PHONY: nette
nette: ## Install a Nette skeleton into nette/app
	$(call composer_create,nette/web-project,nette)

.PHONY: wordpress
wordpress: ## Download WordPress core into wordpress/app
	docker run --rm -v "$(CURDIR)/wordpress/app:/app" -w /app alpine \
	  sh -c 'wget -qO- https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1 -C /app'

.PHONY: help
help: ## List the available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
