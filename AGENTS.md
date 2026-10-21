# Working on the PHP images

- `docker-bake.hcl` builds FPM and SSH together. Keep costly dependencies in
  `php-common`/`ssh-tools`, before final runtime configuration copies.
- Use `make build test` for native local validation (OrbStack or Docker).
  Defaults: PHP 8.4 / Node 22. Override both for other existing pairs.
- Use `make check` and lint `.github/workflows/*.yml` with actionlint after CI edits.
  `docker buildx bake --print` checks resolved targets without building images.
- `build-versions.json` defines version pairs. CI resolves immutable base digests
  and matching AMD64/ARM64 patches before builds; manual releases require an
  explicit expected-version map. Run `make test-resolver` after resolver edits.
- `docker-bake.ci.hcl` is CI-only: cache scopes include version and architecture.
  CI uses native GitHub runners, no QEMU or remote EC2 builder.
- PR builds receive no registry secrets. Publish only from `master`, after tests.
- Preserve the intentional igbinary-last installation order (Redis must not
  compile igbinary support). Keep SSH host keys out of all image layers.
- Do not publish images or run the release workflow for local validation.
