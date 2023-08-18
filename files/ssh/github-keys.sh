#!/usr/bin/env bash

user=$1
mkdir -p ~/.ssh
echo "# $user@github.com" >>  ~/.ssh/authorized_keys
curl -sL https://github.com/$user.keys >>  ~/.ssh/authorized_keys
