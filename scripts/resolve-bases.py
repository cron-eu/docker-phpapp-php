#!/usr/bin/env python3
"""Freeze official PHP bases and verify their native-platform patch versions."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

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


def parse_expected_versions(raw):
    def unique_branches(pairs):
        result = {}
        for branch, version in pairs:
            if branch in result:
                raise ValueError("Duplicate expected PHP branch: " + branch)
            result[branch] = version
        return result
    return json.loads(raw, object_pairs_hook=unique_branches)


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


def resolve(versions, expected, require_expected_versions=False):
    validate_versions(versions, expected)
    if require_expected_versions and not expected:
        raise ValueError("An explicit nonempty expected-version map is required")
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
            raise ValueError("PHP %s is not ready on both platforms: AMD64=%s, ARM64=%s" %
                             (minor, amd64, arm64))
        if not amd64.startswith(minor + "."):
            raise ValueError("PHP %s tag contains unexpected version %s" % (minor, amd64))
        if minor in expected and amd64 != expected[minor]:
            raise ValueError("PHP %s expected %s, but both platforms provide %s" %
                             (minor, expected[minor], amd64))
        resolved.append({"php": minor, "node": version["node"],
                         "base_image": REPOSITORY + "@" + digest,
                         "expected_php_version": amd64})
        print("Verified PHP %s on AMD64 and ARM64 at %s" % (amd64, digest), file=sys.stderr)
    return resolved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--versions-file", default="build-versions.json")
    parser.add_argument("--expected-versions", default="{}",
                        help='Exact patches to require, e.g. {"8.4":"8.4.26"}; selects those branches')
    parser.add_argument("--require-expected-versions", action="store_true",
                        help="Reject an empty patch map for manually requested releases")
    parser.add_argument("--summary", help="Append verified base information to this Markdown file")
    args = parser.parse_args()
    try:
        versions = json.loads(Path(args.versions_file).read_text())
        expected = parse_expected_versions(args.expected_versions)
        resolved = resolve(versions, expected, args.require_expected_versions)
        if args.summary:
            with Path(args.summary).open("a") as summary:
                summary.write("## Verified PHP bases\n\n| PHP branch | AMD64 patch | ARM64 patch | Base index |\n")
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
