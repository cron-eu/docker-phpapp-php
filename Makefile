# Native local builds; command-line assignments override these defaults.
PHP_VERSION ?= 8.4
NODE_VERSION ?= 22
PLATFORMS ?=
FPM_IMAGE ?= croneu/phpapp-fpm:php-$(PHP_VERSION)
SSH_IMAGE ?= croneu/phpapp-ssh:php-$(PHP_VERSION)-node-$(NODE_VERSION)
BUILDX_OPTIONS ?= --load

export PHP_VERSION NODE_VERSION PLATFORMS FPM_IMAGE SSH_IMAGE

.PHONY: build build-fpm build-ssh test check
build:
	docker buildx bake $(BUILDX_OPTIONS)

build-fpm:
	docker buildx bake $(BUILDX_OPTIONS) fpm

build-ssh:
	docker buildx bake $(BUILDX_OPTIONS) ssh

# Run after loading images into the local Docker engine.
test:
	bash tests/smoke.sh "$(FPM_IMAGE)" "$(SSH_IMAGE)"

check:
	docker buildx bake --check
