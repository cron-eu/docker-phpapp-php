#!/usr/bin/env bash
set -e

# ENTRYPOINT for the ssh container

# If arguments have been passed, we want to "run" them instead of starting the SSH daemon
# Also do not do any time consuming actions (network activity)

IS_RUN=0
test $# -ge 1 && IS_RUN=1

# User running the application
APP_USER=application
APP_USER_HOME=$(eval echo "~${APP_USER}")

if [[ ! $IS_RUN ]]; then
  echo "* Activating 'application' user and SSH keys"

  # Unlock 'application' account
  PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)
  echo "${APP_USER}:$PASS" | chpasswd
fi

# Make sure 'application' home directory exists...
mkdir -p $APP_USER_HOME && chown $APP_USER $APP_USER_HOME

if [[ ! $IS_RUN ]] && [[ -z "${IMPORT_GITLAB_PUB_KEYS}" ]] && [[ -z "${IMPORT_GITHUB_PUB_KEYS}" ]]; then
  echo "WARNING: env variable \$IMPORT_GITHUB_PUB_KEYS or IMPORT_GITLAB_PUB_KEYS is not set. Please set it to have access to this container via SSH."
fi

# -------------------------------------------------------------------------
# Load ssh-agent in case of calling this with
#   `docker run -e SSH_PRIVATE_KEY=$SSH_PRIVATE_KEY croneu/phpapp-ssh:php-7.4-node-16 composer install`

if [ ! -z "$SSH_PRIVATE_KEY" ]; then
  echo "* loading SSH agent and SSH private key"
  eval $(ssh-agent -s)
  ssh-add <(echo "$SSH_PRIVATE_KEY") || exit 1
fi

# -------------------------------------------------------------------------
# Import SSH keys from Gitlab

if [[ ! -z "${IMPORT_GITLAB_PUB_KEYS}" && ! $IS_RUN ]] ; then
  # Read passed to container ENV IMPORT_GITLAB_PUB_KEYS variable with coma-separated
  # user list and add public key(s) for these users to authorized_keys on 'application' account.
  for user in $(echo $IMPORT_GITLAB_PUB_KEYS | tr "," "\n"); do
    echo "* importing SSH key: $user@$IMPORT_GITLAB_SERVER"
    su ${APP_USER} -c "/gitlab-keys.sh $user $IMPORT_GITLAB_SERVER"
  done
fi

# -------------------------------------------------------------------------
# Import SSH keys from Github

if [[ ! -z "${IMPORT_GITHUB_PUB_KEYS}" && ! $IS_RUN ]]; then
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
EOF

  if ! ct --version | grep 2.5.4 >/dev/null
  then
    # this is not compatible with ct v2.5.x (PHP 7.0), so only add this on other versions
    cat <<EOF >> $APP_USER_HOME/.my.cnf
[mysql]
database=${DB_NAME}
EOF
  fi

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
# Start the real entrypoint

if [[ $IS_RUN ]]; then
  # with arguments, start the command passed to me
  test -d /app && cd /app
  exec gosu "$APP_USER" "$@"
  exit 0
fi

# Start the SSH Daemon

# Start SSHD, making sure to pass docker variables to logged in users
mkdir -p -m0755 /var/run/sshd

# Make the passed env variables available also for users logging in
# Skip "dangerous" variables, skip the ones with spaces  as this would require a more complex loading
# mechanism and only keep lines with "=" in it (skip multi-line variables)
env | egrep -v '^(PATH|HOME|PWD|USER|SHELL|HOSTNAME|LOGNAME)' | egrep -v ' ' | grep '=' > /etc/environment

exec /usr/sbin/sshd -e -D
