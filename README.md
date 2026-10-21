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

* `croneu/phpapp-fpm:php-8.4`
* `croneu/phpapp-fpm:php-8.3`
* `croneu/phpapp-fpm:php-8.2`
* `croneu/phpapp-fpm:php-8.1`
* `croneu/phpapp-fpm:php-7.4` - no longer updated
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
* ffi
* gd
* gettext
* igbinary
* imagick
* intl
* ldap
* mcrypt (no longer with PHP 8.4 - long deprecated)
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
* vips
* xdebug
* yaml
* zip

All extensions are enabled by default. If you want to only disable some of them,
you can use the setting `PHP_DISABLE_EXTENSIONS` in the environment variables.
If you want to override the list of enabled extensions, you can use the
`PHP_EXTENSIONS` environment variable.

Additionally, the image includes the following utilities for TYPO3 specific workflows:

* GraphicsMagick
* curl
* exiftool
* ghostscript (for PDF processing with GraphicsMagick)
* locales-all
* poppler-utils (for pdftotext etc)

### SSH image (image `croneu/phpapp-ssh`)

Available tags:

* `croneu/phpapp-ssh:php-8.4-node-22`
* `croneu/phpapp-ssh:php-8.3-node-20`
* `croneu/phpapp-ssh:php-8.2-node-18`
* `croneu/phpapp-ssh:php-8.1-node-16`
* `croneu/phpapp-ssh:php-7.4-node-16` - no longer updated
* `croneu/phpapp-ssh:php-7.4-node-14` - no longer updated
* `croneu/phpapp-ssh:php-7.4-node-12` - no longer updated
* `croneu/phpapp-ssh:php-7.4-node-10` - no longer updated
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
* redis-cli
* GraphicsMagick
* exiftool, poppler-utils

### SSH image for onetime tasks

You can also use the `phpapp-ssh` image to run one-time containers to execute certain tasks
with the same setup. I.e.:

```
docker run -v .:/app --rm croneu/phpapp-ssh:php-8.4-node-22 make test 
```

Or in docker-compose:
```
  test:
    image: croneu/phpapp-ssh:php-8.4-node-22
    command: make test
    volumes:
      - .:/app
```

## Usage

### Application root

Application root is `/app`. Application runs as user `application` (uid=1000).

### Settings (through environment variables)

| Setting                                    | Image    | Default     | Description                                                                                                                              |
|--------------------------------------------|----------|-------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `XDEBUG_MODE`                              | fpm, ssh | debug       | Or set to `develop` (slow) or `none` to turn it off completely. See https://xdebug.org/docs/all_settings#mode                            |
| `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` | ssh      |             | These will create a `.my.cnf` for the user. You can use the same variables in your  `docker-compose.yml` to configure the MariaDB image. |
| `APPLICATION_UID`, `APPLICATION_GID`       | fpm, ssh | 1000, 1000  | UID and GID for the application user. Change to match your local user in case you use bind-mounts (Linux only)                           |
| `IMPORT_GITLAB_SERVER`                     | ssh      | git.cron.eu | Gitlab instance to import SSH key from                                                                                                   |
| `IMPORT_GITLAB_PUB_KEYS`                   | ssh      |             | Gitlab user to import SSH keys from                                                                                                      |
| `IMPORT_GITHUB_PUB_KEYS`                   | ssh      |             | GitHub user to import SSH keys from                                                                                                      |
| `IMPORT_PUB_KEYS`                          | ssh      |             | Additional SSH public keys to load, comma separated                                                                                      |
| `SSH_CONFIG`                               | ssh      |             | The whole content of the `.ssh/config` file                                                                                              |
| `SSH_KNOWN_HOSTS`                          | ssh      |             | The whole content of the `.ssh/known_hosts` file                                                                                         |
| `SSH_PRIVATE_KEY`                          | ssh      |             | A SSH private key to load in an `ssh-agent`, useful if you run a SSH container with commands                                             |                                                    |
| `ENV`                                      | ssh      |             | The name of the environment to show on the shell prompt                                                                                  |
| `PHP_INI_OVERRIDE`                         | fpm, ssh |             | Allow overriding php.ini settings. Simply the multiline content for a php.ini here. Use "\n" for multiline i.e. in ECS                   |
| `PHP_FPM_OVERRIDE`                         | fpm      |             | Allow overriding php-fpm pool settings. The multiline content for php-fpm.conf here. Use "\n" for multiline i.e. in ECS                  |
| `PHP_EXTENSIONS`                           | fpm, ssh | (all)       | Comma separated list of PHP extensions to enable (if this is not set, all are enabled).                                                  |
| `PHP_DISABLE_EXTENSIONS`                   | fpm, ssh |             | Comma separated list of PHP extensions to disable (in case you keep all enabled, you can disable individual ones, i.e. igbinary).        |
| `PHPINI__xxx__yyy`                         | fpm, ssh |             | Set php.ini setting `xxx.yyy` (always lower cased)                                                                                       |
| `PHPFPM__xxx__yyy`                         | fpm      |             | Set php-fpm pool setting `xxx.yyy` (always lower cased)                                                                                  |

The `PHPINI__...` and `PHPFPM__...` allow to set individual settings for `php.ini`
and `php-fpm.conf` (pool settings) using individual environment variables. Just
replace the `.` in the settings by `__`. Examples:

Upper case allowed (will be lower-cased):
```
PHPINI__SESSION__SAVE_HANDLER=redis
PHPINI__SESSION__SAVE_PATH='"tcp://redis:6379?persistent=1&weight=1&database=10&prefix=PHPSESSID:"'
PHPINI__REDIS__SESSION__LOCKING_ENABLED=1
```

Or (lower case also fine):
```
PHPFPM__request_terminate_timeout=30s
PHPFPM__pm__max_children=15
```

**Note**: make sure that potentially required double quotes `"` are part of the
"string" that ends up in the ENV variable, so quote as necessary, because this
string is copied "as is" to the ini files. See example above for the
`PHPINI__SESSION__SAVE_PATH` - this would be the syntax for a `.env` file.

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

Docker Bake builds the FPM and SSH targets together, sharing the PHP extensions
and runtime packages. The SSH toolchain is installed before entrypoints and PHP
configuration are copied, so editing runtime configuration keeps expensive layers
cached. The final target names remain `php-fpm` and `ssh`.

### Build and test locally

Requirements: Docker with Buildx/Bake (Docker Desktop or OrbStack), Make, and Bash.
The default build uses the builder's native architecture, PHP 8.4, and Node 22.
Both images are loaded into the local Docker engine:

```bash
make build
make test
```

BuildKit retains its normal local builder cache; exporting a `.buildx-cache`
directory is no longer required. Repeat `make build` for a warm build. To inspect
cache hits, use `make build BUILDX_OPTIONS="--load --progress=plain"`.

Build another existing version pair, or just one target:

```bash
make build test PHP_VERSION=8.3 NODE_VERSION=20
make build-fpm PHP_VERSION=8.4
make build-ssh PHP_VERSION=8.4 NODE_VERSION=22
```

`make test` expects both images to be loaded. It checks PHP extensions and version,
startup warnings, Xdebug on/off, extension controls, PHP/FPM environment overrides,
the FastCGI healthcheck, SSH command identity and tools, executable permissions,
and SSH host key generation, uniqueness, and persistence. It creates temporary
containers and a volume, cleans them up on exit, and publishes no host ports.
The suite mounts an empty `/app`; application integration can be checked with the
Compose example in `example-app/`.

Override tags to keep experimental images separate:

```bash
make build test FPM_IMAGE=phpapp-fpm:local SSH_IMAGE=phpapp-ssh:local
```

Other useful commands:

```bash
make check                         # BuildKit Dockerfile checks
docker buildx bake --print          # Resolved local build configuration
```

Set `PLATFORMS=linux/amd64` or `PLATFORMS=linux/arm64` to select one architecture.
Local `--load` and runtime tests are intended for one architecture at a time.
Building a foreign architecture locally requires emulation or a matching native
builder; CI always uses matching native runners.

### CI and publishing

- `build-only.yml` runs on pull requests to `master`, or manually. It builds and
  tests every existing PHP/Node pair on native AMD64 and ARM64 GitHub runners.
  It receives no Docker Hub credentials and never publishes images.
- `build-images.yml` is the shared implementation. Each version/architecture job
  builds both targets with Bake, loads them, and runs the same `make test` suite.
- `build-and-push.yml` runs on pushes to `master`, or manually on `master`.
  After each pair passes, it exports the cached build to unique architecture
  candidate tags, verifying that exported image configurations match the tested
  local images. All architecture jobs must succeed before manifests update
  `croneu/phpapp-fpm:php-X.Y` and `croneu/phpapp-ssh:php-X.Y-node-N`.
  Docker Hub descriptions update once per repository after all manifests succeed.

The existing version pairs are unchanged: 8.4/22, 8.3/20, 8.2/18, and 8.1/16.
The release workflow requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets.
`SSH_PRIVATE_KEY`, the append-builder action, and `arm.d.cron.eu` are no longer
used by these workflows. Remove the obsolete secret and retire the EC2 builder
once a GitHub run has validated the replacement.

`docker-bake.ci.hcl` adds GitHub cache API v2 with separate image/version/architecture
scopes. SSH imports its own scope and the matching FPM scope. GitHub enforces
branch/ref cache isolation; PR merge-ref caches do not populate the release
branch's cache. The first run under a new scope is expected to be cold. Compare
an unchanged rerun and an entrypoint-only change to confirm cache reuse.

Candidate tags include the workflow run ID and attempt. Rerunning only failed jobs
can reuse successful digest artifacts from the same run (artifacts are retained
for one day); after expiration, rerun the whole workflow. Candidate tags remain
in Docker Hub until removed through a registry retention policy.

SSH host keys are generated only when the SSH daemon starts, and existing keys
are preserved. A recreated container normally gets a new identity. Mount a
persistent volume at `/etc/ssh` if stable identity is required; initialize a fresh
volume with this image's SSH configuration, and manage that configuration across
image upgrades. One-off command containers do not generate host keys.

## MIT Licence

See the [LICENSE](LICENSE) file.

## Author

Ernesto Baschny, [cron IT GmbH](https://www.cron.eu)
