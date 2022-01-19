#!/usr/bin/env bash

user=$1
mkdir -p ~/.ssh
echo "# $user@github.com" >>  ~/.ssh/authorized_keys
curl -s https://github.com/$user.keys >>  ~/.ssh/authorized_keys
