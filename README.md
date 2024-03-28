# cron PHP application docker images - PHP

## Abstract

Part of the `docker-phpapp` image suite.

Opinionated docker images for running PHP-Applications used at cron IT GmbH -
mostly for TYPO3 and Neos projects but generic for any PHP application.

Images for **amd64** and **arm64** (i.e. they also run on Apple M1).

Born out of the desire to have good (and simple) multiplatform images for our developers
to work on our PHP projects (also on M1 / ARM machines) locally and to run these same
images on container platforms (mostly AWS ECS) in production.

Main goals:
- Production-ready - run same images for local development and in production
- As near as possible to the official images
- Configuration through environment variables
- Using best practices which proved good with our PHP projects in the last years

## Docker Images

In this repo:

* `croneu/phpapp-fpm`
* `croneu/phpapp-ssh`

Related:

* `croneu/phpapp-web` see https://github.com/cron-eu/docker-phpapp-web
* `croneu/phpapp-db` see https://github.com/cron-eu/docker-phpapp-db

### PHP-FPM (image `croneu/phpapp-fpm`)

Available tags:

* `croneu/phpapp-fpm:php-8.2`
* `croneu/phpapp-fpm:php-8.1`
* `croneu/phpapp-fpm:php-7.4`
* `croneu/phpapp-fpm:php-7.3` - no longer updated
* `croneu/phpapp-fpm:php-7.2` - no longer updated
* `croneu/phpapp-fpm:php-7.0` - no longer updated

PHP runs as PHP-FPM (image `croneu/phpapp-fpm`), based on the offical images. 
Use the `croneu/phpapp-web` container to be able to access this from a browser.

This image includes the following additional extensions:

* apcu
* bcmath
* bz2
* calendar
* exif
* gd
* gettext
* igbinary
* imagick
* intl
* mcrypt
* mysqli
* opcache
* pcntl
* pdo_mysql
* redis
* shmop
* soap
* sockets
* sysvmsg
* sysvsem
* sysvshm
* uuid
* xdebug
* yaml
* zip

Additionally, it includes the following utilities for TYPO3 specific workflows:

* GraphicsMagick
* curl
* exiftool
* ghostscript (for PDF processing with GraphicsMagick)
* locales-all
* poppler-utils (for pdftotext etc)

### SSH image (image `croneu/phpapp-ssh`)

Available tags:

* `croneu/phpapp-ssh:php-8.3-node-20`
* `croneu/phpapp-ssh:php-8.2-node-18`
* `croneu/phpapp-ssh:php-8.1-node-16`
* `croneu/phpapp-ssh:php-7.4-node-16`
* `croneu/phpapp-ssh:php-7.4-node-14`
* `croneu/phpapp-ssh:php-7.4-node-12`
* `croneu/phpapp-ssh:php-7.4-node-10`
* `croneu/phpapp-ssh:php-7.3-node-10` - no longer updated
* `croneu/phpapp-ssh:php-7.2-node-10` - no longer updated
* `croneu/phpapp-ssh:php-7.0-node-14` - no longer updated

You can start a container for SSH'ing into it for development purposes with the image
`croneu/phpapp-ssh`. It is based off the `phpapp-fpm` image (thus it contains the exact same
version and extensions installed) but additionally includes a set of tools to work with
the application from the command line:

* Composer v2
* NodeJS
* Convenience tools: git, zip, make, ping, less, vi, wget, joe, jq, rsync, patch
* clitools from WebdevOps
* MySQL client
* GraphicsMagick
* exiftool, poppler-utils

### SSH image for onetime tasks

You can also use the `phpapp-ssh` image to run one-time containers to execute certain tasks
with the same setup. I.e.:

```
docker run -v .:/app --rm croneu/phpapp-ssh:php-7.4-node-16 make test 
```

Or in docker-compose:
```
  test:
    image: croneu/phpapp-ssh:php-7.4-node-16
    command: make test
    volumes:
      - .:/app
```

## Usage

### Application root

Application root is `/app`. Application runs as user `application` (uid=1000).

### Settings (through environment variables)

| Setting                                | Image    | Default     | Description                                                                                                                              |
|----------------------------------------|----------|-------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `XDEBUG_MODE`                          | fpm, ssh | debug       | Or set to `develop` (slow) or `none` to turn it off completely. See https://xdebug.org/docs/all_settings#mode                            |
| `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` | ssh      |             | These will create a `.my.cnf` for the user. You can use the same variables in your  `docker-compose.yml` to configure the MariaDB image. |
| `APPLICATION_UID`, `APPLICATION_GID`       | fpm, ssh | 1000, 1000  | UID and GID for the application user. Change to match your local user in case you use bind-mounts (Linux only)                           |
| `IMPORT_GITLAB_SERVER`                 | ssh      | git.cron.eu | Gitlab instance to import SSH key from                                                                                                   |
| `IMPORT_GITLAB_PUB_KEYS`               | ssh      |             | Gitlab user to import SSH keys from                                                                                                      |
| `IMPORT_GITHUB_PUB_KEYS`               | ssh      |             | GitHub user to import SSH keys from                                                                                                      |
| `SSH_CONFIG`                           | ssh      |             | The whole content of the `.ssh/config` file                                                                                              |
| `SSH_KNOWN_HOSTS`                      | ssh      |             | The whole content of the `.ssh/known_hosts` file                                                                                         |
| `SSH_PRIVATE_KEY`                      | ssh      |             | A SSH private key to load in an `ssh-agent`, useful if you run a SSH container with commands                                             |                                                    |
| `ENV`                                  | ssh      |             | The name of the environment to show on the shell prompt                                                                                  |
| `PHP_INI_OVERRIDE`                     | fpm, ssh |             | Allow overriding php.ini settings. Simply the multiline content for a php.ini here. Use "\n" for multiline i.e. in ECS                   |
| `PHP_FPM_OVERRIDE`                     | fpm      |             | Allow overriding php-fpm pool settings. The multiline content for php-fpm.conf here. Use "\n" for multiline i.e. in ECS                  |

## Example usage

Copy the files from `example-app/` folder to your application, tweak, and you are
ready to go.

### Web Server

The `web` container will start a web-server listening on the port you specified in
`docker-compose.yml` (default is 8000 and 8443).

To access the web-server, make sure you have a DNS entry in your local `/etc/hosts`
or local DNS server:

`/etc/hosts` for `docker-machine`:
```
192.168.99.100 my-app.vm
```

`/etc/hosts` for Docker for Mac or locally on Linux:
```
127.0.0.1 my-app.vm
```

Then you can access the web-server:

* http://my-app.vm:8080/
* https://my-app.vm:8443/

### SSH Access

You can then SSH into the container using for example:

```bash
ssh -A -p 1122 application@my-app.vm
```

----

## Docker Image Development

Build is triggered automatically via Github Actions.

To create them locally for testing purposes (and load created images to your docker).

Image `croneu/phpapp-ssh:php-8.1-node-16`:
```
make build-ssh PHP_VERSION=8.1 NODE_VERSION=16
```

Image `croneu/phpapp-fpm:php-8.1`:
```
make build-fpm PHP_VERSION=8.1
```

### Test the Docker Image

To test the image you can use the supplied docker-compose files in the `example-app` directory.

## MIT Licence

See the [LICENSE](LICENSE) file.

## Author

Ernesto Baschny, [cron IT GmbH](https://www.cron.eu)
