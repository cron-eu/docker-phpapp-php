#!/bin/sh

# ENTRYPOINT for the FPM container

# Override some PHP settings
. /entrypoint-extras.sh

# Start the "real" entrypoint
. /usr/local/bin/docker-php-entrypoint
