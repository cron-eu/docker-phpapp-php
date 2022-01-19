
PLATFORMS=linux/arm64/v8,linux/amd64

# Defaults:
PHP_VERSION=7.4
NODE_VERSION=14

#BUILDX_OPTIONS=--push
DOCKER_CACHE=--cache-from "type=local,src=.buildx-cache" --cache-to "type=local,dest=.buildx-cache"

build:
	docker buildx build $(DOCKER_CACHE) $(BUILDX_OPTIONS) \
		--platform $(PLATFORMS) \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--tag croneu/phpapp-fpm:php-$(PHP_VERSION) \
		--target php-fpm \
		.
	docker buildx build $(DOCKER_CACHE) $(BUILDX_OPTIONS) \
		--platform $(PLATFORMS) \
		--build-arg PHP_VERSION=$(PHP_VERSION) --build-arg NODE_VERSION=$(NODE_VERSION) \
		--tag croneu/phpapp-ssh:php-$(PHP_VERSION)-node-$(NODE_VERSION) \
		--target ssh \
		.
