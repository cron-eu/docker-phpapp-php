
# For local testing

PLATFORMS=linux/amd64
#PLATFORMS=linux/arm64/v8

# Defaults:
PHP_VERSION=8.1
NODE_VERSION=16

BUILDX_OPTIONS=--load
DOCKER_CACHE_PATH=.buildx-cache
DOCKER_CACHE=--cache-from "type=local,src=$(DOCKER_CACHE_PATH)" --cache-to "type=local,mode=max,dest=$(DOCKER_CACHE_PATH)"

build-fpm:
	docker buildx build $(DOCKER_CACHE) $(BUILDX_OPTIONS) \
		--platform $(PLATFORMS) \
		--build-arg PHP_MINOR_VERSION=$(PHP_VERSION) \
		--tag croneu/phpapp-fpm:php-$(PHP_VERSION) \
		--target php-fpm \
		.

build-ssh:
	docker buildx build $(DOCKER_CACHE) $(BUILDX_OPTIONS) \
		--platform $(PLATFORMS) \
		--build-arg PHP_MINOR_VERSION=$(PHP_VERSION) --build-arg NODE_VERSION=$(NODE_VERSION) \
		--tag croneu/phpapp-ssh:php-$(PHP_VERSION)-node-$(NODE_VERSION) \
		--target ssh \
		.
