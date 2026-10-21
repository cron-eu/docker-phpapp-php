#!/usr/bin/env bash
# Run against loaded images; PHP_VERSION/NODE_VERSION assert minor/major versions.
# PHP and container-side shell expressions must not expand on the host.
# shellcheck disable=SC2016
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 FPM_IMAGE SSH_IMAGE" >&2
  exit 2
fi
FPM_IMAGE=$1
SSH_IMAGE=$2
TEST_ID="phpapp-smoke-$$-$(date +%s)"
TEST_LOG=$(mktemp)
CONTAINERS=""
KEY_VOLUME="${TEST_ID}-keys"

cleanup() {
  result=$?
  trap - EXIT
  if [[ $result != 0 ]]; then
    echo "Smoke test failed; last command output:" >&2
    cat "$TEST_LOG" >&2
    for name in $CONTAINERS; do
      docker logs "$name" >&2 2>/dev/null || true
    done
  fi
  for name in $CONTAINERS; do
    docker rm -f "$name" >/dev/null 2>&1 || true
  done
  docker volume rm "$KEY_VOLUME" >/dev/null 2>&1 || true
  rm -f "$TEST_LOG"
  exit "$result"
}
trap cleanup EXIT

# Capture stderr as well: PHP startup warnings must fail otherwise successful runs.
check() {
  if ! "$@" >"$TEST_LOG" 2>&1; then
    return 1
  fi
  if grep -Ei 'PHP (Warning|Fatal error|Parse error|Startup)|Unable to load dynamic library|Cannot load Zend' "$TEST_LOG"; then
    return 1
  fi
}

wait_for() {
  local name=$1
  shift
  local attempt
  for ((attempt = 0; attempt < 45; attempt++)); do
    if check docker exec "$name" "$@"; then
      return 0
    fi
    if [[ $(docker inspect --format '{{.State.Running}}' "$name") != true ]]; then
      return 1
    fi
    sleep 1
  done
  return 1
}

for image in "$FPM_IMAGE" "$SSH_IMAGE"; do
  echo "Checking PHP runtime: $image"
  check docker run --rm --tmpfs /app "$image" php -r '
    if ($argv[1] !== "" && $argv[1] !== (PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION)) {
      fwrite(STDERR, "Unexpected PHP version: " . PHP_VERSION . "\n"); exit(1);
    }
    $expected = ["apcu", "bcmath", "bz2", "calendar", "exif", "FFI", "gd",
      "gettext", "igbinary", "imagick", "intl", "ldap", "mysqli", "Zend OPcache",
      "pcntl", "pdo_mysql", "redis", "shmop", "soap", "sockets", "sysvmsg",
      "sysvsem", "sysvshm", "uuid", "vips", "yaml", "zip"];
    if (PHP_VERSION_ID < 80400) { $expected[] = "mcrypt"; }
    foreach ($expected as $extension) {
      if (!extension_loaded($extension)) {
        fwrite(STDERR, "Missing extension: $extension\n"); exit(1);
      }
    }
    if (extension_loaded("xdebug")) { exit(1); }
    if (defined("Redis::SERIALIZER_IGBINARY")) {
      fwrite(STDERR, "Redis unexpectedly compiled with igbinary support\n"); exit(1);
    }
  ' "${PHP_VERSION:-}"
  check docker run --rm --entrypoint sh "$image" -ec '
    for script in /entrypoint.sh /entrypoint-extras.sh /usr/local/bin/php-fpm-healthcheck; do
      test -x "$script"
      test "$(stat -c %u "$script")" = 0
      test -z "$(find "$script" -perm /022)"
    done
  '
  check docker run --rm --tmpfs /app -e XDEBUG_MODE=develop "$image" \
    php -r 'exit(extension_loaded("xdebug") ? 0 : 1);'
  check docker run --rm --tmpfs /app -e XDEBUG_MODE=off "$image" \
    php -r 'exit(!extension_loaded("xdebug") ? 0 : 1);'
  check docker run --rm --tmpfs /app -e PHP_DISABLE_EXTENSIONS=redis "$image" \
    php -r 'exit(!extension_loaded("redis") && extension_loaded("igbinary") ? 0 : 1);'
  check docker run --rm --tmpfs /app -e PHP_EXTENSIONS=redis "$image" \
    php -r 'exit(extension_loaded("redis") && !extension_loaded("igbinary") ? 0 : 1);'
  check docker run --rm --tmpfs /app -e PHPINI__memory_limit=192M "$image" \
    php -r 'exit(ini_get("memory_limit") === "192M" ? 0 : 1);'
done

echo "Checking FPM startup, configuration overrides, and FastCGI healthcheck"
FPM_CONTAINER="${TEST_ID}-fpm"
CONTAINERS="$CONTAINERS $FPM_CONTAINER"
docker run -d --name "$FPM_CONTAINER" -e PHPFPM__pm__max_children=7 "$FPM_IMAGE" >/dev/null
wait_for "$FPM_CONTAINER" php-fpm-healthcheck
check docker exec "$FPM_CONTAINER" php-fpm -t
check docker exec "$FPM_CONTAINER" sh -ec \
  'grep -Fx "pm.max_children = 7" /usr/local/etc/php-fpm.d/www.conf'

echo "Checking SSH command mode, toolchain, and executable permissions"
check docker run --rm --tmpfs /app -e "EXPECTED_NODE_VERSION=${NODE_VERSION:-}" "$SSH_IMAGE" sh -ec '
  test "$(id -u)" = "$(id -u application)"
  test "$(id -u)" != 0
  test "$(pwd)" = /app
  test "$(stat -c %a /usr/local/bin/ct)" = 755
  test "$(stat -c %u /usr/local/bin/ct)" = 0
  test -x /usr/local/bin/composer
  test "$(stat -c %u /usr/local/bin/composer)" = 0
  test -z "$(find /usr/local/bin/composer -perm /022)"
  composer --version
  node --version
  if test -n "$EXPECTED_NODE_VERSION"; then
    case "$(node --version)" in
      "v$EXPECTED_NODE_VERSION".*) ;;
      *) echo "Unexpected Node version" >&2; exit 1 ;;
    esac
  fi
  npm --version
  ct --version
  test -z "$(find /etc/ssh -name "ssh_host_*_key*")"
'
check docker run --rm --entrypoint sh "$SSH_IMAGE" -ec \
  'test -z "$(find /etc/ssh -name "ssh_host_*_key*")"'

echo "Checking SSH daemon startup and independent host identities"
docker volume create "$KEY_VOLUME" >/dev/null
SSH_ONE="${TEST_ID}-ssh-one"
SSH_TWO="${TEST_ID}-ssh-two"
CONTAINERS="$CONTAINERS $SSH_ONE $SSH_TWO"
docker run -d --name "$SSH_ONE" --tmpfs /app \
  --mount "type=volume,src=$KEY_VOLUME,dst=/etc/ssh" "$SSH_IMAGE" >/dev/null
docker run -d --name "$SSH_TWO" --tmpfs /app "$SSH_IMAGE" >/dev/null
for name in "$SSH_ONE" "$SSH_TWO"; do
  wait_for "$name" sh -ec 'pgrep -x sshd >/dev/null && /usr/sbin/sshd -t'
done
fingerprint() {
  docker exec "$1" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}'
}
FIRST_KEY=$(fingerprint "$SSH_ONE")
SECOND_KEY=$(fingerprint "$SSH_TWO")
test -n "$FIRST_KEY"
test -n "$SECOND_KEY"
test "$FIRST_KEY" != "$SECOND_KEY"

echo "Checking persisted SSH identity after container recreation"
docker rm -f "$SSH_ONE" >/dev/null
docker run -d --name "$SSH_ONE" --tmpfs /app \
  --mount "type=volume,src=$KEY_VOLUME,dst=/etc/ssh" "$SSH_IMAGE" >/dev/null
wait_for "$SSH_ONE" sh -ec 'pgrep -x sshd >/dev/null && /usr/sbin/sshd -t'
test "$(fingerprint "$SSH_ONE")" = "$FIRST_KEY"

echo "Runtime smoke tests passed"
