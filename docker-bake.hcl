variable "PHP_VERSION" {
  default = "8.4"
}

variable "NODE_VERSION" {
  default = "22"
}

# Empty means the builder's native platform. Local --load builds one platform.
variable "PLATFORMS" {
  default = ""
}

variable "FPM_IMAGE" {
  default = "croneu/phpapp-fpm:php-${PHP_VERSION}"
}

variable "SSH_IMAGE" {
  default = "croneu/phpapp-ssh:php-${PHP_VERSION}-node-${NODE_VERSION}"
}

group "default" {
  targets = ["fpm", "ssh"]
}

target "common" {
  context = "."
  dockerfile = "Dockerfile"
  pull = true
  platforms = PLATFORMS == "" ? [] : split(",", PLATFORMS)
  args = {
    PHP_MINOR_VERSION = PHP_VERSION
    NODE_VERSION = NODE_VERSION
  }
}

target "fpm" {
  inherits = ["common"]
  target = "php-fpm"
  tags = [FPM_IMAGE]
}

target "ssh" {
  inherits = ["common"]
  target = "ssh"
  tags = [SSH_IMAGE]
}
