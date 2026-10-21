#!/usr/bin/env python3
"""Freeze official PHP bases and verify their native-platform patch versions."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPOSITORY = "docker.io/library/php"
DIGEST = re.compile(r"sha256:[0-9a-f]{64}")
MINOR = re.compile(r"[0-9]+\.[0-9]+")
PATCH = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


def inspect(reference, field):
    """Read registry metadata without downloading or executing image layers."""
    command = ["docker", "buildx", "imagetools", "inspect", reference,
               "--format", "{{json .%s}}" % field]
    for attempt in range(3):
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    check=True, timeout=60)
            return json.loads(result.stdout)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            if attempt == 2:
                detail = getattr(error, "stderr", None) or str(error)
                raise ValueError("Cannot inspect %s: %s" % (reference, detail)) from error
            print("Registry inspection failed for %s; retrying" % reference,
                  file=sys.stderr)
            time.sleep(attempt + 1)


class UpstreamNotReady(ValueError):
    """Official Docker images have not caught up with the required PHP release."""


def fetch_release(minor):
    request = urllib.request.Request(
        "https://www.php.net/releases/index.php?json&version=" + minor,
        headers={"Accept": "application/json", "User-Agent": "phpapp-build-workflow"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError) as error:
            if isinstance(error, urllib.error.HTTPError) and error.code not in (408, 429, 500, 502, 503, 504):
                raise ValueError("Cannot read PHP release metadata: " + str(error)) from error
            if attempt == 2:
                raise ValueError("Cannot read PHP release metadata: " + str(error)) from error
            print("PHP release metadata unavailable for %s; retrying" % minor, file=sys.stderr)
            time.sleep(attempt + 1)


def announced_patch(metadata, minor):
    value = metadata.get("version") if isinstance(metadata, dict) else None
    if not isinstance(value, str) or not PATCH.fullmatch(value) or not value.startswith(minor + "."):
        raise ValueError("PHP release metadata needs an exact %s.Z version" % minor)
    return value


def discover_releases(versions):
    """Read announced stable releases once, excluding unsupported configured branches."""
    validate_versions(versions, {})
    highest = max((item["php"] for item in versions), key=lambda value: tuple(map(int, value.split("."))))
    first = fetch_release(highest)
    announced_patch(first, highest)
    supported = first.get("supported_versions")
    if (not isinstance(supported, list) or not supported
            or any(not isinstance(value, str) or not MINOR.fullmatch(value) for value in supported)):
        raise ValueError("PHP release metadata needs a supported_versions list of PHP branches")
    expected, skipped = {}, []
    for item in versions:
        minor = item["php"]
        if minor not in supported:
            print("Skipping unsupported PHP branch " + minor + " (not listed by php.net)", file=sys.stderr)
            skipped.append(minor)
            continue
        metadata = first if minor == highest else fetch_release(minor)
        expected[minor] = announced_patch(metadata, minor)
    if not expected:
        raise ValueError("No configured PHP branches are supported by php.net")
    print("Announced PHP releases: " + json.dumps(expected, sort_keys=True), file=sys.stderr)
    return expected, skipped


def validate_versions(versions, expected):
    if not isinstance(versions, list) or not versions:
        raise ValueError("Version configuration must be a nonempty list")
    configured = set()
    for version in versions:
        if (not isinstance(version, dict)
                or not isinstance(version.get("php"), str)
                or not MINOR.fullmatch(version["php"])
                or not isinstance(version.get("node"), str)
                or not version["node"].isdigit()):
            raise ValueError("Each configured pair needs PHP X.Y and a Node major string")
        if version["php"] in configured:
            raise ValueError("Duplicate configured PHP branch: " + version["php"])
        configured.add(version["php"])
    if not isinstance(expected, dict):
        raise ValueError("Expected versions must be a JSON object mapping PHP branches to patches")
    for minor, patch in expected.items():
        if minor not in configured:
            raise ValueError("Unknown PHP branch: " + minor)
        if (not isinstance(patch, str) or not PATCH.fullmatch(patch)
                or not patch.startswith(minor + ".")):
            raise ValueError("Expected patch for %s must be a full %s.Z version" % (minor, minor))


def require_digest(value):
    if not isinstance(value, str) or not DIGEST.fullmatch(value):
        raise ValueError("Registry returned an invalid SHA-256 digest")
    return value


def platform_patch(manifest, architecture):
    """Find exactly one native Linux descriptor and read its immutable config."""
    matches = []
    for descriptor in manifest.get("manifests", []):
        platform = descriptor.get("platform", {})
        variants = (None, "", "v8") if architecture == "arm64" else (None, "")
        if (platform.get("os") == "linux"
                and platform.get("architecture") == architecture
                and platform.get("variant") in variants):
            matches.append(descriptor)
    if not matches:
        raise UpstreamNotReady("Base index needs a linux/%s image; found 0" % architecture)
    if len(matches) != 1:
        raise ValueError("Base index needs exactly one linux/%s image; found %s" %
                         (architecture, len(matches)))
    reference = REPOSITORY + "@" + require_digest(matches[0].get("digest"))
    config = inspect(reference, "Image")
    if config.get("os") != "linux" or config.get("architecture") != architecture:
        raise ValueError("Image config does not match linux/" + architecture)
    values = [item.partition("=")[2] for item in config.get("config", {}).get("Env", [])
              if isinstance(item, str) and item.startswith("PHP_VERSION=")]
    if len(values) != 1 or not PATCH.fullmatch(values[0]):
        raise ValueError("Image config needs one exact PHP_VERSION for linux/" + architecture)
    return values[0]


def resolve(versions, expected=None):
    expected = {} if expected is None else expected
    validate_versions(versions, expected)
    resolved = []
    for version in versions:
        minor = version["php"]
        if expected and minor not in expected:
            continue
        tag = REPOSITORY + ":" + minor + "-fpm"
        print("Resolving " + tag, file=sys.stderr)
        manifest = inspect(tag, "Manifest")
        digest = require_digest(manifest.get("digest"))
        amd64 = platform_patch(manifest, "amd64")
        arm64 = platform_patch(manifest, "arm64")
        if amd64 != arm64:
            raise UpstreamNotReady("PHP %s is not ready on both platforms: AMD64=%s, ARM64=%s" %
                             (minor, amd64, arm64))
        if not amd64.startswith(minor + "."):
            raise ValueError("PHP %s tag contains unexpected version %s" % (minor, amd64))
        if minor in expected and amd64 != expected[minor]:
            raise UpstreamNotReady("PHP %s expected %s, but both platforms provide %s" %
                             (minor, expected[minor], amd64))
        resolved.append({"php": minor, "node": version["node"],
                         "base_image": REPOSITORY + "@" + digest,
                         "expected_php_version": amd64})
        print("Verified PHP %s on AMD64 and ARM64 at %s" % (amd64, digest), file=sys.stderr)
    return resolved


def resolve_ready(versions, latest_releases=False, wait_seconds=0):
    if wait_seconds < 0:
        raise ValueError("--wait-seconds must be nonnegative")
    if wait_seconds and not latest_releases:
        raise ValueError("--wait-seconds requires --latest-releases")
    expected, skipped = discover_releases(versions) if latest_releases else ({}, [])
    deadline = time.monotonic() + wait_seconds
    while True:
        try:
            return resolve(versions, expected), skipped
        except UpstreamNotReady as error:
            if not wait_seconds:
                raise
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise UpstreamNotReady("Timed out waiting for official Docker PHP images: " + str(error)) from error
            delay = min(60, remaining)
            print("%s; checking again in %ss" % (error, round(delay)), file=sys.stderr)
            time.sleep(delay)
            if time.monotonic() >= deadline:
                raise UpstreamNotReady("Timed out waiting for official Docker PHP images: " + str(error)) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--versions-file", default="build-versions.json")
    parser.add_argument("--latest-releases", action="store_true",
                        help="Require the latest stable patches announced by php.net for supported branches")
    parser.add_argument("--wait-seconds", type=int, default=0,
                        help="Wait up to this many seconds for Docker readiness, checking at most once per minute")
    parser.add_argument("--summary", help="Append verified base information to this Markdown file")
    args = parser.parse_args()
    try:
        versions = json.loads(Path(args.versions_file).read_text())
        resolved, skipped = resolve_ready(versions, args.latest_releases, args.wait_seconds)
        if args.summary:
            with Path(args.summary).open("a") as summary:
                summary.write("## Verified PHP bases\n\n")
                if skipped:
                    summary.write("Skipped unsupported configured PHP branches: " + ", ".join(skipped) + ".\n\n")
                summary.write("| PHP branch | AMD64 patch | ARM64 patch | Base index |\n")
                summary.write("| --- | --- | --- | --- |\n")
                for item in resolved:
                    summary.write("| %s | %s | %s | `%s` |\n" %
                                  (item["php"], item["expected_php_version"],
                                   item["expected_php_version"], item["base_image"]))
        print(json.dumps(resolved, separators=(",", ":")))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print("Base resolution failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
