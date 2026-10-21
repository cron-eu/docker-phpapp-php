"""Guard against publishing an old or partially updated upstream PHP release."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "resolve_bases", Path(__file__).resolve().parents[1] / "scripts/resolve-bases.py")
bases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bases)

INDEX = "sha256:" + "1" * 64
AMD64 = "sha256:" + "2" * 64
ARM64 = "sha256:" + "3" * 64
PAIRS = [{"php": "8.4", "node": "22"}, {"php": "8.3", "node": "20"}]


def descriptor(architecture, digest, variant=None):
    platform = {"os": "linux", "architecture": architecture}
    if variant:
        platform["variant"] = variant
    return {"platform": platform, "digest": digest}


def manifest():
    return {"digest": INDEX, "manifests": [descriptor("amd64", AMD64),
            descriptor("arm64", ARM64, "v8"),
            {"platform": {"os": "unknown", "architecture": "unknown"}, "digest": INDEX}]}


def image(architecture, version):
    return {"os": "linux", "architecture": architecture,
            "config": {"Env": ["PATH=/usr/bin", "PHP_VERSION=" + version]}}


class ResolveTests(unittest.TestCase):
    def test_freezes_index_and_reads_child_configs_by_digest(self):
        with patch.object(bases, "inspect", side_effect=[manifest(),
                          image("amd64", "8.4.26"), image("arm64", "8.4.26")]) as inspect:
            result = bases.resolve(PAIRS[:1], {})
        self.assertEqual(result, [{"php": "8.4", "node": "22",
                                  "base_image": bases.REPOSITORY + "@" + INDEX,
                                  "expected_php_version": "8.4.26"}])
        self.assertEqual(inspect.call_args_list[0].args,
                         (bases.REPOSITORY + ":8.4-fpm", "Manifest"))
        self.assertEqual(inspect.call_args_list[1].args,
                         (bases.REPOSITORY + "@" + AMD64, "Image"))
        self.assertEqual(inspect.call_args_list[2].args,
                         (bases.REPOSITORY + "@" + ARM64, "Image"))

    def test_expected_map_selects_only_requested_branch(self):
        with patch.object(bases, "inspect", side_effect=[manifest(),
                          image("amd64", "8.3.35"), image("arm64", "8.3.35")]) as inspect:
            result = bases.resolve(PAIRS, {"8.3": "8.3.35"})
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["php"], "8.3")
        self.assertEqual(inspect.call_args_list[0].args[0], bases.REPOSITORY + ":8.3-fpm")

    def test_platforms_must_agree(self):
        with patch.object(bases, "inspect", side_effect=[manifest(),
                          image("amd64", "8.4.27"), image("arm64", "8.4.26")]):
            with self.assertRaisesRegex(ValueError, "not ready on both platforms"):
                bases.resolve(PAIRS[:1], {})

    def test_old_patch_cannot_satisfy_security_release(self):
        with patch.object(bases, "inspect", side_effect=[manifest(),
                          image("amd64", "8.4.26"), image("arm64", "8.4.26")]):
            with self.assertRaisesRegex(ValueError, "expected 8.4.27"):
                bases.resolve(PAIRS[:1], {"8.4": "8.4.27"})

    def test_missing_platform(self):
        data = manifest()
        data["manifests"] = data["manifests"][:1]
        with patch.object(bases, "inspect", side_effect=[data, image("amd64", "8.4.26")]):
            with self.assertRaisesRegex(ValueError, "linux/arm64.*found 0"):
                bases.resolve(PAIRS[:1], {})

    def test_ambiguous_platform(self):
        data = manifest()
        data["manifests"].append(descriptor("amd64", INDEX))
        with patch.object(bases, "inspect", return_value=data):
            with self.assertRaisesRegex(ValueError, "linux/amd64.*found 2"):
                bases.resolve(PAIRS[:1], {})

    def test_invalid_digest(self):
        data = manifest()
        data["digest"] = "mutable-tag"
        with patch.object(bases, "inspect", return_value=data):
            with self.assertRaisesRegex(ValueError, "invalid SHA-256"):
                bases.resolve(PAIRS[:1], {})

    def test_config_architecture_must_match_descriptor(self):
        with patch.object(bases, "inspect", side_effect=[manifest(), image("arm64", "8.4.26")]):
            with self.assertRaisesRegex(ValueError, "does not match linux/amd64"):
                bases.resolve(PAIRS[:1], {})

    def test_php_tag_cannot_point_to_other_minor(self):
        with patch.object(bases, "inspect", side_effect=[manifest(),
                          image("amd64", "8.3.35"), image("arm64", "8.3.35")]):
            with self.assertRaisesRegex(ValueError, "unexpected version"):
                bases.resolve(PAIRS[:1], {})

    def test_invalid_expectations_fail_before_any_registry_access(self):
        invalid = [[], None, "8.4.26", {"8.5": "8.5.1"}, {"8.4": 26},
                   {"8.4": "8.4"}, {"8.4": "8.3.35"}, {"8.4": "8.4.26RC1"}]
        for expected in invalid:
            with self.subTest(expected=expected), patch.object(bases, "inspect") as inspect:
                with self.assertRaises(ValueError):
                    bases.resolve(PAIRS, expected)
                inspect.assert_not_called()

    def test_manual_release_requires_explicit_patch_map(self):
        with patch.object(bases, "inspect") as inspect:
            with self.assertRaisesRegex(ValueError, "explicit nonempty expected-version map"):
                bases.resolve(PAIRS, {}, require_expected_versions=True)
            inspect.assert_not_called()

    def test_missing_or_duplicate_php_environment_is_rejected(self):
        for env in [[], ["PHP_VERSION=8.4.26", "PHP_VERSION=8.4.27"], ["PHP_VERSION=8.4"]]:
            config = image("amd64", "8.4.26")
            config["config"]["Env"] = env
            with self.subTest(env=env), patch.object(bases, "inspect", side_effect=[manifest(), config]):
                with self.assertRaisesRegex(ValueError, "one exact PHP_VERSION"):
                    bases.resolve(PAIRS[:1], {})

    @patch.object(bases.time, "sleep")
    @patch.object(bases.subprocess, "run")
    def test_registry_errors_are_retried_with_bounded_attempts(self, run, sleep):
        run.side_effect = subprocess.CalledProcessError(1, "docker", stderr="temporary registry failure")
        with self.assertRaisesRegex(ValueError, "Cannot inspect"):
            bases.inspect("php:8.4-fpm", "Manifest")
        self.assertEqual(run.call_count, 3)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2])

    @patch.object(bases.time, "sleep")
    @patch.object(bases.subprocess, "run")
    def test_registry_retry_can_succeed(self, run, sleep):
        run.side_effect = [subprocess.CalledProcessError(1, "docker"),
                           subprocess.CompletedProcess([], 0, stdout='{"digest":"value"}')]
        self.assertEqual(bases.inspect("php:8.4-fpm", "Manifest"), {"digest": "value"})
        self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
