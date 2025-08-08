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

# Start the "real" entrypoint
. /usr/local/bin/docker-php-entrypoint
