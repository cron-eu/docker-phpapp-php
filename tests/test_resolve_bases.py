"""Guard against publishing an old or partially updated upstream PHP release."""

import importlib.util
from pathlib import Path
import subprocess
import io
import json
import urllib.error
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
            with self.assertRaisesRegex(bases.UpstreamNotReady, "not ready on both platforms"):
                bases.resolve(PAIRS[:1], {})

    def test_old_patch_cannot_satisfy_security_release(self):
        with patch.object(bases, "inspect", side_effect=[manifest(),
                          image("amd64", "8.4.26"), image("arm64", "8.4.26")]):
            with self.assertRaisesRegex(bases.UpstreamNotReady, "expected 8.4.27"):
                bases.resolve(PAIRS[:1], {"8.4": "8.4.27"})

    def test_missing_platform(self):
        data = manifest()
        data["manifests"] = data["manifests"][:1]
        with patch.object(bases, "inspect", side_effect=[data, image("amd64", "8.4.26")]):
            with self.assertRaisesRegex(bases.UpstreamNotReady, "linux/arm64.*found 0"):
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
        invalid = [[], "8.4.26", {"8.5": "8.5.1"}, {"8.4": 26},
                   {"8.4": "8.4"}, {"8.4": "8.3.35"}, {"8.4": "8.4.26RC1"}]
        for expected in invalid:
            with self.subTest(expected=expected), patch.object(bases, "inspect") as inspect:
                with self.assertRaises(ValueError):
                    bases.resolve(PAIRS, expected)
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


class ReleaseDiscoveryTests(unittest.TestCase):
    def test_latest_releases_skips_eol_and_uses_highest_configured_branch(self):
        pairs = [{"php": "8.1", "node": "16"}, *PAIRS]
        first = {"version": "8.4.27", "supported_versions": ["8.2", "8.3", "8.4", "8.5"]}
        with patch.object(bases, "fetch_release", side_effect=[first, {"version": "8.3.36"}]) as fetch:
            expected, skipped = bases.discover_releases(pairs)
        self.assertEqual(expected, {"8.4": "8.4.27", "8.3": "8.3.36"})
        self.assertEqual(skipped, ["8.1"])
        self.assertEqual([call.args[0] for call in fetch.call_args_list], ["8.4", "8.3"])

    def test_latest_mode_rejects_docker_images_that_agree_on_old_patch(self):
        release = {"version": "8.4.27", "supported_versions": ["8.4"]}
        with patch.object(bases, "fetch_release", return_value=release), \
                patch.object(bases, "inspect", side_effect=[manifest(), image("amd64", "8.4.26"),
                                                         image("arm64", "8.4.26")]):
            with self.assertRaisesRegex(bases.UpstreamNotReady, "expected 8.4.27"):
                bases.resolve_ready(PAIRS[:1], latest_releases=True)

    def test_invalid_release_metadata_fails_without_registry_fallback(self):
        invalid = [None, [], {}, {"version": "8.4"}, {"version": "8.4.27RC1"},
                   {"version": "8.3.36"}, {"version": "8.4.27", "supported_versions": "8.4"},
                   {"version": "8.4.27", "supported_versions": []},
                   {"version": "8.4.27", "supported_versions": [8.4]}]
        for metadata in invalid:
            with self.subTest(metadata=metadata), patch.object(bases, "fetch_release", return_value=metadata), \
                    patch.object(bases, "inspect") as inspect:
                with self.assertRaises(ValueError):
                    bases.resolve_ready(PAIRS[:1], latest_releases=True)
                inspect.assert_not_called()

    def test_each_supported_branch_needs_its_own_valid_patch(self):
        first = {"version": "8.4.27", "supported_versions": ["8.4", "8.3"]}
        with patch.object(bases, "fetch_release", side_effect=[first, {"version": "8.4.27"}]):
            with self.assertRaisesRegex(ValueError, "8.3.Z"):
                bases.discover_releases(PAIRS)

    def test_no_supported_configured_branch_fails(self):
        first = {"version": "8.4.27", "supported_versions": ["8.5"]}
        with patch.object(bases, "fetch_release", return_value=first):
            with self.assertRaisesRegex(ValueError, "No configured PHP branches"):
                bases.discover_releases(PAIRS)

    def test_default_mode_keeps_eol_branch_without_release_api(self):
        pairs = [{"php": "8.1", "node": "16"}]
        with patch.object(bases, "fetch_release") as fetch, \
                patch.object(bases, "inspect", side_effect=[manifest(), image("amd64", "8.1.34"),
                                                         image("arm64", "8.1.34")]):
            resolved, skipped = bases.resolve_ready(pairs)
        self.assertEqual(resolved[0]["php"], "8.1")
        self.assertEqual(skipped, [])
        fetch.assert_not_called()

    @patch.object(bases.time, "sleep")
    @patch.object(bases.urllib.request, "urlopen")
    def test_release_api_network_failure_never_falls_back(self, urlopen, sleep):
        urlopen.side_effect = urllib.error.URLError("unavailable")
        with patch.object(bases, "inspect") as inspect:
            with self.assertRaisesRegex(ValueError, "Cannot read PHP release metadata"):
                bases.resolve_ready(PAIRS, latest_releases=True)
        self.assertEqual(urlopen.call_count, 3)
        inspect.assert_not_called()
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2])

    @patch.object(bases.urllib.request, "urlopen")
    def test_release_api_uses_https_with_timeout(self, urlopen):
        metadata = {"version": "8.4.27", "supported_versions": ["8.4"]}
        urlopen.return_value.__enter__.return_value = io.StringIO(json.dumps(metadata))
        self.assertEqual(bases.fetch_release("8.4"), metadata)
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://www.php.net/releases/index.php?json&version=8.4")
        self.assertEqual(urlopen.call_args.kwargs["timeout"], 30)

    @patch.object(bases.time, "sleep")
    @patch.object(bases.urllib.request, "urlopen")
    def test_release_api_invalid_json_is_not_retried(self, urlopen, sleep):
        urlopen.return_value.__enter__.return_value = io.StringIO("not JSON")
        with self.assertRaises(ValueError):
            bases.fetch_release("8.4")
        self.assertEqual(urlopen.call_count, 1)
        sleep.assert_not_called()


class ReadinessWaitTests(unittest.TestCase):
    def test_wait_succeeds_and_freezes_announced_versions_once(self):
        clock = [0]
        expected = {"8.4": "8.4.27"}
        result = [{"php": "8.4", "expected_php_version": "8.4.27"}]
        with patch.object(bases, "discover_releases", return_value=(expected, [])) as discover, \
                patch.object(bases, "resolve", side_effect=[bases.UpstreamNotReady("old patch"), result]) as resolve, \
                patch.object(bases.time, "monotonic", side_effect=lambda: clock[0]), \
                patch.object(bases.time, "sleep", side_effect=lambda delay: clock.__setitem__(0, clock[0] + delay)) as sleep:
            self.assertEqual(bases.resolve_ready(PAIRS[:1], True, 120), (result, []))
        discover.assert_called_once_with(PAIRS[:1])
        self.assertEqual(resolve.call_count, 2)
        self.assertEqual([call.args[1] for call in resolve.call_args_list], [expected, expected])
        sleep.assert_called_once_with(60)

    def test_wait_timeout_is_bounded_and_shortens_last_sleep(self):
        clock = [0]
        with patch.object(bases, "discover_releases", return_value=({"8.4": "8.4.27"}, [])) as discover, \
                patch.object(bases, "resolve", side_effect=bases.UpstreamNotReady("old patch")) as resolve, \
                patch.object(bases.time, "monotonic", side_effect=lambda: clock[0]), \
                patch.object(bases.time, "sleep", side_effect=lambda delay: clock.__setitem__(0, clock[0] + delay)) as sleep:
            with self.assertRaisesRegex(bases.UpstreamNotReady, "Timed out"):
                bases.resolve_ready(PAIRS[:1], True, 65)
        discover.assert_called_once()
        self.assertEqual(resolve.call_count, 2)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [60, 5])
        self.assertEqual(clock[0], 65)

    def test_wait_does_not_retry_invalid_registry_metadata(self):
        with patch.object(bases, "discover_releases", return_value=({"8.4": "8.4.27"}, [])), \
                patch.object(bases, "resolve", side_effect=ValueError("invalid digest")) as resolve, \
                patch.object(bases.time, "sleep") as sleep:
            with self.assertRaisesRegex(ValueError, "invalid digest"):
                bases.resolve_ready(PAIRS[:1], True, 120)
        resolve.assert_called_once()
        sleep.assert_not_called()

    def test_invalid_wait_options_fail_before_discovery(self):
        for latest, seconds in [(False, 60), (True, -1)]:
            with self.subTest(latest=latest, seconds=seconds), patch.object(bases, "discover_releases") as discover:
                with self.assertRaises(ValueError):
                    bases.resolve_ready(PAIRS[:1], latest, seconds)
                discover.assert_not_called()


if __name__ == "__main__":
    unittest.main()
