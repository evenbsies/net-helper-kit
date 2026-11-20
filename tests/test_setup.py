#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Offline regression tests for the one-command setup entry point."""
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="nhk-setup-")
        self.work = Path(self.tmp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.calls = self.work / "calls"
        self.env = os.environ.copy()
        self.env.update(
            PATH=f"{self.bin}:{os.environ['PATH']}",
            HOME=str(self.work / "home"),
            MOCK_CALLS=str(self.calls),
        )
        # These commands must never be reached by --plan-only, or before the
        # non-Alpine preflight rejection.  The mocks are deliberately noisy.
        for name in ("apk", "curl"):
            mock = self.bin / name
            mock.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$0 $*\" >> \"$MOCK_CALLS\"\n"
                "exit 99\n"
            )
            mock.chmod(0o700)
        self.fixture = self.work / "hysteria"
        self.fixture.write_bytes(b"offline hysteria fixture\n")
        self.fixture.chmod(0o700)
        self.sha = hashlib.sha256(self.fixture.read_bytes()).hexdigest()

    def tearDown(self):
        self.tmp.cleanup()

    def run_setup(self, *args, data="", shell=False):
        command = ["sh", str(ROOT / "setup.sh"), *args] if shell else [str(ROOT / "setup.sh"), *args]
        return subprocess.run(
            command,
            input=data,
            text=True,
            capture_output=True,
            env=self.env,
            cwd=str(self.work),
            timeout=15,
        )

    def plan_answers(self):
        # host, internal port, external port, BBR profile, upstream, binary, sha, TLS mode
        return "\n".join(
            ["node.example.com", "24443", "34443", "standard", "1.1.1.1", str(self.fixture), self.sha, "pin"]
        ) + "\n"

    def test_help_is_available_both_executable_and_sh_invocation(self):
        for shell in (False, True):
            with self.subTest(shell=shell):
                result = self.run_setup("--help", shell=shell)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("一条命令", result.stdout)
                self.assertIn("--plan-only", result.stdout)
                self.assertIn("BBR 档位", result.stdout)
                self.assertEqual(result.stderr, "")

    def test_invalid_argument_fails_immediately_without_side_effects(self):
        result = self.run_setup("--not-a-real-option")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("用法", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.work / "home").exists())

    def test_plan_only_without_output_routes_to_guide_and_menu_help(self):
        result = self.run_setup("--plan-only", data="4\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("net-helper-kit", result.stdout)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.work / "home").exists())

    def test_plan_only_menu_rejects_shared_domain_without_network_or_install(self):
        result = self.run_setup("--plan-only", data="2\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue("用法" in result.stderr or "不支持" in result.stderr or "未联网" in result.stderr,
                        result.stdout + result.stderr)
        self.assertFalse(self.calls.exists(), "plan-only menu must not invoke apk/curl")
        self.assertFalse((self.work / "home").exists())

    def test_plan_only_output_generates_real_fixture_plan_offline(self):
        output = self.work / "plan"
        result = self.run_setup("--plan-only", str(output), data=self.plan_answers())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((output / "client.json").is_file())
        self.assertTrue((output / "server.yaml").is_file())
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
        self.assertFalse(self.calls.exists(), "--plan-only must not invoke apk/curl")

    def test_plan_only_preserves_existing_output_and_refuses_overwrite(self):
        output = self.work / "existing-plan"
        output.mkdir(mode=0o700)
        marker = output / "keep-me"
        marker.write_text("do not replace\n")
        result = self.run_setup("--plan-only", str(output), data=self.plan_answers())
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), "do not replace\n")
        self.assertEqual(list(output.iterdir()), [marker])

    def test_plan_only_keeps_private_artifact_permissions(self):
        output = self.work / "private-plan"
        result = self.run_setup("--plan-only", str(output), data=self.plan_answers())
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("client.json", "server.key", "node-uri.txt"):
            self.assertEqual(stat.S_IMODE((output / name).stat().st_mode), 0o600, name)

    @unittest.skipIf(Path("/etc/alpine-release").exists(), "Alpine runner exercises deployment path, not Ubuntu rejection")
    def test_default_deployment_rejects_unsupported_context_before_apk_or_curl(self):
        result = self.run_setup(data="")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(
            ("Alpine" in result.stderr if os.geteuid() == 0 else "root" in result.stderr),
            result.stdout + result.stderr,
        )
        self.assertFalse(self.calls.exists(), "need_root_alpine must run before apk/curl")
        self.assertFalse((self.work / "home").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
