#!/usr/bin/env bash
set -e

# ENTRYPOINT for the ssh container

# User running the application
APP_USER=application
APP_USER_HOME=$(eval echo "~${APP_USER}")

echo "Activating 'application' user and SSH keys"

# Unlock 'application' account
PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
echo "${APP_USER}:$PASS" | chpasswd

# Make sure 'application' home directory exists...
mkdir -p $APP_USER_HOME && chown $APP_USER $APP_USER_HOME

if [ -z "${IMPORT_GITLAB_PUB_KEYS}" ] && [ -z "${IMPORT_GITHUB_PUB_KEYS}" ]; then
  echo "WARNING: env variable \$IMPORT_GITHUB_PUB_KEYS or IMPORT_GITLAB_PUB_KEYS is not set. Please set it to have access to this container via SSH."
fi

# -------------------------------------------------------------------------
# Import SSH keys from Gitlab

if [ ! -z "${IMPORT_GITLAB_PUB_KEYS}" ] ; then
  # Read passed to container ENV IMPORT_GITLAB_PUB_KEYS variable with coma-separated
  # user list and add public key(s) for these users to authorized_keys on 'application' account.
  for user in $(echo $IMPORT_GITLAB_PUB_KEYS | tr "," "\n"); do
    echo "* importing SSH key: $user@$IMPORT_GITLAB_SERVER"
    su ${APP_USER} -c "/gitlab-keys.sh $user $IMPORT_GITLAB_SERVER"
  done
fi

# -------------------------------------------------------------------------
# Import SSH keys from Github

if [ ! -z "${IMPORT_GITHUB_PUB_KEYS}" ]; then
  # Read passed to container ENV IMPORT_GITHUB_PUB_KEYS variable with coma-separated
  # user list and add public key(s) for these users to authorized_keys on 'application' account.
  for user in $(echo $IMPORT_GITHUB_PUB_KEYS | tr "," "\n"); do
    echo "* importing SSH key: $user@github.com"
    su ${APP_USER} -c "/github-keys.sh $user"
  done
fi

# -------------------------------------------------------------------------
# Import SSH user settings from env

if [ ! -z "${SSH_CONFIG}" ]; then
  echo "* Configuring .ssh/config"
  mkdir -p $APP_USER_HOME/.ssh
  echo "${SSH_CONFIG}" > $APP_USER_HOME/.ssh/config
  chmod 644 $APP_USER_HOME/.ssh/config
fi
if [ ! -z "${SSH_KNOWN_HOSTS}" ]; then
  echo "* Configuring .ssh/known_hosts"
  mkdir -p $APP_USER_HOME/.ssh
  echo "${SSH_KNOWN_HOSTS}" > $APP_USER_HOME/.ssh/known_hosts
  chmod 644 $APP_USER_HOME/.ssh/known_hosts
fi

# -------------------------------------------------------------------------
# Generate a .my.cnf if required

# There are DB credentials in the environment, make them available to the ${APP_USER}'s my.cnf
if [ ! -z "${DB_USER}" ]; then
  # Create a .my.cnf
  cat <<EOF > $APP_USER_HOME/.my.cnf
[client]
host=${DB_HOST}
port=${DB_PORT}
user=${DB_USER}
password=${DB_PASS}

[mysql]
database=${DB_NAME}
EOF
  chown ${APP_USER}. $APP_USER_HOME/.my.cnf

  # Create a .clitools.ini
  cat <<EOF > $APP_USER_HOME/.clitools.ini
[config]
domain_dev = "vm:8000"

[db]
dsn = "mysql:host=${DB_HOST};port=${DB_PORT}"
username = "${DB_USER}"
password = "${DB_PASS}"
EOF
fi

# -------------------------------------------------------------------------
# Make sure the /app directory is writeable by the user
test -d /app && chown ${APP_USER}. /app

# -------------------------------------------------------------------------
# Extra PHP initialization

source /entrypoint-extras.sh

# -------------------------------------------------------------------------
# Start the SSH Daemon

# Start SSHD, making sure to pass docker variables to logged in users
mkdir -p -m0755 /var/run/sshd

# Make the passed env variables available also for users logging in
# Skip "dangerous" variables, skip the ones with spaces  as this would require a more complex loading
# mechanism and only keep lines with "=" in it (skip multi-line variables)
env | egrep -v '^(PATH|HOME|PWD|USER|SHELL|HOSTNAME|LOGNAME)' | egrep -v ' ' | grep '=' > /etc/environment

exec /usr/sbin/sshd -e -D
