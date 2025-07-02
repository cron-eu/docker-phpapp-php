#!/bin/sh

# Some initialization for all php containers in phpapp
# Called from the entrypoint.sh in both the FPM and SSH containers
#
# Mainly tweaking php settings based on ENV variables

# Controls which extensions are enabled.

if [ ! -z "${PHP_EXTENSIONS}" ]; then
  # If PHP_EXTENSIONS is set: only enable the ones specified

  echo "* PHP_EXTENSIONS: $PHP_EXTENSIONS"
  echo "* Disabling all extensions and enabling only specified ones."

  # First, disable all extensions by renaming them
  if ls /usr/local/etc/php/conf.d/docker-php-ext-*.ini 1> /dev/null 2>&1; then
    for file in /usr/local/etc/php/conf.d/docker-php-ext-*.ini; do
      mv "$file" "$file.disabled"
    done
  fi

  # Now, enable the extensions listed in PHP_EXTENSIONS
  for ext in $(echo "$PHP_EXTENSIONS" | sed -e 's/,/ /g'); do
    disabled_ext_file="/usr/local/etc/php/conf.d/docker-php-ext-$ext.ini.disabled"
    enabled_ext_file="/usr/local/etc/php/conf.d/docker-php-ext-$ext.ini"

    if [ -f "$disabled_ext_file" ]; then
      echo "* Enabling PHP extension: $ext"
      mv "$disabled_ext_file" "$enabled_ext_file"
    elif [ -f "$enabled_ext_file" ]; then
      # This case should not happen if the above disabling loop worked, but as a fallback.
      echo "* PHP extension $ext was already enabled."
    else
      echo "* WARNING: PHP extension $ext not found, cannot enable."
    fi
  done
else
  # If PHP_EXTENSIONS is not set, all extensions are enabled by default.

  # Enable all extensions which might have been disabled at some point first
  if ls /usr/local/etc/php/conf.d/*php-ext*.disabled 1> /dev/null 2>&1; then
    for file in /usr/local/etc/php/conf.d/*php-ext*.disabled; do
      mv "$file" "${file%.disabled}"
    done
  fi
  # Disable extensions based on PHP_DISABLE_EXTENSIONS
  if [ ! -z "${PHP_DISABLE_EXTENSIONS}" ]; then
    for ext in $(echo $PHP_DISABLE_EXTENSIONS | sed -e 's/,/ /g'); do
      if [ -f "/usr/local/etc/php/conf.d/docker-php-ext-$ext.ini" ]; then
        echo "* Disabling PHP extension: $ext"
        mv /usr/local/etc/php/conf.d/docker-php-ext-$ext.ini /usr/local/etc/php/conf.d/docker-php-ext-$ext.ini.disabled
      else
        echo "* WARNING: PHP extension $ext not found, cannot disable"
      fi
    done
  fi
fi

# Special handling for XDEBUG through XDEBUG_MODE:

# Really disable XDEBUG if not required
if [ -z "${XDEBUG_MODE}" ] || [ "${XDEBUG_MODE}" = "off" ]; then
  # completely not load xdebug if its off
  rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
else
  echo "* Enabling XDEBUG: $XDEBUG_MODE"
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
  test -d /app && chown application: -R /app
  echo "* Fixing permissions in /home/application"
  test -d /home/application && find /home/application/ -mount -not -user application -exec chown application: {} \;
fi

if [ ! -z "${PHP_INI_OVERRIDE}" ]; then
  echo "${PHP_INI_OVERRIDE}" | sed -e 's/\\n/\n/g' > /usr/local/etc/php/conf.d/zz-02-custom.ini
fi
