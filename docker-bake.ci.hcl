# Overlay for GitHub Actions only. Branch/ref isolation is enforced by GitHub.
variable "CACHE_ARCH" {
  default = "amd64"
}

target "fpm" {
  cache-from = ["type=gha,version=2,scope=fpm-php-${PHP_VERSION}-${CACHE_ARCH}"]
  cache-to = ["type=gha,version=2,mode=max,scope=fpm-php-${PHP_VERSION}-${CACHE_ARCH}"]
}

target "ssh" {
  cache-from = [
    "type=gha,version=2,scope=ssh-php-${PHP_VERSION}-node-${NODE_VERSION}-${CACHE_ARCH}",
    "type=gha,version=2,scope=fpm-php-${PHP_VERSION}-${CACHE_ARCH}",
  ]
  cache-to = ["type=gha,version=2,mode=max,scope=ssh-php-${PHP_VERSION}-node-${NODE_VERSION}-${CACHE_ARCH}"]
}
