#!/usr/bin/env bash

#
# Source: https://github.com/rtlong, https://gist.github.com/rtlong/6790049
# Usage: /gitlab-keys.sh | bash -s <gitlab username>
#
IFS="$(printf '\n\t')"

user=$1
server=$2
api_response=$(curl -k -sSLi https://${server}/${user}.keys)
keys=$(echo "$api_response" | grep -o -E 'ssh-\w+\s+[^\"]+')

if [ -z "$keys" ]; then
  echo "WARNING: ${server} doesn't have any keys for '$user' user."
else
  [ -d ~/.ssh ] || mkdir ~/.ssh
  [ -f ~/.ssh/authorized_keys ] || touch ~/.ssh/authorized_keys
  echo "# ${user}@${server}" >>  ~/.ssh/authorized_keys

  for key in $keys; do
    grep -q "$key" ~/.ssh/authorized_keys || echo "$key ${user}@${server}" >> ~/.ssh/authorized_keys
  done
fi
