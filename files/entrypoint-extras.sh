#!/bin/sh

# Some initialization for all php containers in phpapp
# Called from the entrypoint.sh in both the FPM and SSH containers
#
# Mainly tweaking php settings based on ENV variables

# Really disable XDEBUG if not required
if [ -z "${XDEBUG_MODE}" ] || [ "${XDEBUG_MODE}" = "off" ]; then
  # completely not load xdebug if its off
  rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
else
  echo "* enabling XDEBUG: $XDEBUG_MODE"
  echo "zend_extension=xdebug.so" > /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
fi

if [ ! -z "${APPLICATION_UID}" ]; then
  echo "* Change uid of 'application' user to $APPLICATION_UID"
  usermod -u $APPLICATION_UID application
fi
if [ ! -z "${APPLICATION_GID}" ]; then
  echo "* Change gid of 'application' user to $APPLICATION_GID"
  groupmod -g $APPLICATION_GID application
fi

if [ ! -z "${APPLICATION_UID}" ] || [ ! -z "${APPLICATION_GID}" ]; then
  echo "* Fixing permissions in /app"
  test -d /app && chown application. -R /app
  echo "* Fixing permissions in /home/application"
  test -d /home/application && find /home/application/ -mount -not -user application -exec chown application. {} \;
fi
