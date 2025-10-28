#!/bin/sh

# ENTRYPOINT for the FPM container

# Override some PHP settings
. /entrypoint-extras.sh

PHP_FPM_POOL_CONF=/usr/local/etc/php-fpm.d/www.conf

# Configure FPM, first the defaults:
cat <<EOF > $PHP_FPM_POOL_CONF
[www]
user = application
group = application
listen = 127.0.0.1:9000
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.status_path = /status
EOF

# Allow overriding this with settings coming from PHP_FPM_OVERRIDE
if [ ! -z "${PHP_FPM_OVERRIDE}" ]; then
  echo "* Customizing FPM with PHP_FPM_OVERRIDE:"
  echo "- - - 8< - - -"
  echo "${PHP_FPM_OVERRIDE}" | sed -e 's/\\n/\n/g'
  echo "- - - 8< - - -"
  echo "; Customizations from PHP_FPM_OVERRIDE:" >> $PHP_FPM_POOL_CONF
  echo "${PHP_FPM_OVERRIDE}" | sed -e 's/\\n/\n/g' >> $PHP_FPM_POOL_CONF
fi
unset PHP_FPM_OVERRIDE

# Fill from ENV variables prefixed with PHPFPM__
# Examples:
#   PHPFPM__pm__max_children=15 => pm.max_children = 15
#   PHPFPM__request_terminate_timeout=30s => request_terminate_timeout = 30s
#   PHPFPM__slowlog=/data/php-logs/slow.log => slowlog = /data/php-logs/slow.log
#
if env | grep -q '^PHPFPM__'; then
  # Ensure the custom ini exists (and keep any content already written above)
  touch "$CUSTOM_INI"
  # Iterate over all matching env var names only
  for name in $(printenv | awk -F= '/^PHPFPM__/ {print $1}'); do
    value=$(printenv "$name")
    # Transform key: PHPINI__this__setting => this.setting
    key=${name#PHPFPM__}
    key=$(printf '%s' "$key" | sed 's/__/./g')
    key=${key,,}
    # Append as "key = value" (value is written as-is; quote in ENV if needed)
    printf '* PHP-FPM pool setting: %s = %s\n' "$key" "$value"
    printf '%s = %s\n' "$key" "$value" >> "$PHP_FPM_POOL_CONF"
    # Unset them, not relevant to the running containers
    unset "$name"
  done
fi

# Start the "real" entrypoint
. /usr/local/bin/docker-php-entrypoint
