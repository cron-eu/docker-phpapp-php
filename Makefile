
PLATFORMS=linux/arm64/v8,linux/amd64

# Defaults:
PHP_VERSION=7.4
NODE_VERSION=14

#BUILDX_OPTIONS=--push
DOCKER_CACHE_PATH=.buildx-cache
DOCKER_CACHE=--cache-from "type=local,src=$(DOCKER_CACHE_PATH)" --cache-to "type=local,mode=max,dest=$(DOCKER_CACHE_PATH)"

test:
	echo DOCKER_CACHE_PATH: $(DOCKER_CACHE_PATH)
	echo DOCKER_CACHE: $(DOCKER_CACHE)

build-fpm:
	docker buildx build $(DOCKER_CACHE) $(BUILDX_OPTIONS) \
		--platform $(PLATFORMS) \
		--build-arg PHP_MINOR_VERSION=$(PHP_VERSION) \
		--build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) \
		--tag croneu/phpapp-fpm:php-$(PHP_VERSION) \
		--target php-fpm \
		.

build-ssh:
	docker buildx build $(DOCKER_CACHE) $(BUILDX_OPTIONS) \
		--platform $(PLATFORMS) \
		--build-arg PHP_MINOR_VERSION=$(PHP_VERSION) --build-arg NODE_VERSION=$(NODE_VERSION) \
		--build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) \
		--tag croneu/phpapp-ssh:php-$(PHP_VERSION)-node-$(NODE_VERSION) \
		--target ssh \
		.
