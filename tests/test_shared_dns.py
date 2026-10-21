#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""DuckDNS integration tests; all curl calls are replaced by an offline mock."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "123e4567-e89b-12d3-a456-426614174000"


class SharedDnsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="nhk-shared-")
        self.work = Path(self.tmp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.mock = self.bin / "curl"
        self.mock.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$@" > "$MOCK_ARGV"\n'
            'cat > "$MOCK_STDIN"\n'
            'case "${MOCK_RESULT:-OK}" in timeout) exit 28;; KO) printf KO;; *) printf OK;; esac\n'
        )
        self.mock.chmod(0o700)
        self.fixture = self.work / "hysteria"
        self.fixture.write_bytes(b"offline fixture binary\n")
        self.fixture.chmod(0o700)
        self.sha = hashlib.sha256(self.fixture.read_bytes()).hexdigest()
        self.env = os.environ.copy()
        self.env.update(PATH=f"{self.bin}:{os.environ['PATH']}", BASE=str(ROOT),
                        MOCK_ARGV=str(self.work / "argv"), MOCK_STDIN=str(self.work / "stdin"))

    def tearDown(self):
        self.tmp.cleanup()

    def run_shell(self, function, *args, data="YES\n", result="OK"):
        self.env["MOCK_RESULT"] = result
        code = f'. "$1/lib/common.sh"; . "$1/lib/shared_dns.sh"; shift; {function} "$@"'
        return subprocess.run(["sh", "-c", code, "sh", str(ROOT), *map(str, args)],
                              input=data, text=True, capture_output=True, env=self.env)

    def shared_input(self, slug="edge-node"):
        return (f"{slug}\n8.8.8.8\n{TOKEN}\nYES\n"
                f"1024\n1024\n1.1.1.1\n{self.fixture}\n{self.sha}\npin\n")

    def test_success_real_wizard_shared_plan_and_get(self):
        profile, output = self.work / "profile", self.work / "output"
        r = self.run_shell("shared_plan", output, profile, data=self.shared_input())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((profile / "domain").read_text().strip(), "edge-node")
        self.assertEqual((profile / "ipv4").read_text().strip(), "8.8.8.8")
        self.assertEqual((profile / "token").read_text().strip(), TOKEN)
        self.assertEqual(stat.S_IMODE(profile.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((profile / "token").stat().st_mode), 0o600)
        self.assertTrue((output / "server.yaml").is_file())
        self.assertEqual(json.loads((output / "client.json").read_text())["server"], "edge-node.duckdns.org:1024")
        argv = (self.work / "argv").read_text().splitlines()
        self.assertEqual(argv[0], "--disable")
        self.assertNotIn(TOKEN, " ".join(argv))
        self.assertIn("--get", (self.work / "argv").read_text().splitlines())
        config = (self.work / "stdin").read_text()
        self.assertIn("domains=edge-node", config)
        self.assertIn(TOKEN, config)
        self.assertNotIn(TOKEN, r.stdout + r.stderr)

    def test_hyphen_slug_and_strict_uuid(self):
        profile, output = self.work / "profile", self.work / "output"
        r = self.run_shell("shared_plan", output, profile, data=self.shared_input("a-b"))
        self.assertEqual(r.returncode, 0, r.stderr)
        bad = TOKEN[:8] + "--" + TOKEN[10:]
        r = self.run_shell("shared_plan", self.work / "bad-out", self.work / "bad-profile",
                           data=f"slug\n8.8.8.8\n{bad}\n")
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.work / "bad-profile").exists())

    def test_ko_and_timeout_uncertain_result_do_not_save_profile(self):
        for result in ("KO", "timeout"):
            with self.subTest(result=result):
                profile = self.work / result
                r = self.run_shell("shared_plan", self.work / (result + "-out"), profile,
                                   data=f"slug\n8.8.8.8\n{TOKEN}\nYES\n", result=result)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse(profile.exists())
                self.assertIn("无法确认远程结果", r.stderr)
                self.assertNotIn(TOKEN, r.stdout + r.stderr)

    def test_plan_failure_keeps_profile_and_does_not_offer_shared_plan_overwrite(self):
        profile, output = self.work / "kept-profile", self.work / "failed-output"
        data = (f"slug\n8.8.8.8\n{TOKEN}\nYES\n1024\n1024\n1.1.1.1\n"
                f"{self.fixture}\n{'0' * 64}\npin\n")
        r = self.run_shell("shared_plan", output, profile, data=data)
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((profile / "token").is_file())
        self.assertIn("普通 plan 输入正确域名", r.stderr)
        self.assertNotIn("shared-plan 重试", r.stderr)

    def test_paths_reject_symlink_duplicate_slash_overlap_and_source_tree(self):
        target = self.work / "target"
        target.mkdir()
        link = self.work / "link"
        link.symlink_to(target, target_is_directory=True)
        cases = [
            (self.work / "out//x", self.work / "profile"),
            (link / "out", self.work / "profile2"),
            (self.work / "same", self.work / "same"),
            (self.work / "nested", self.work / "nested" / "profile"),
            (ROOT / "new-output", self.work / "profile3"),
            (self.work / "output4", ROOT / "profile4"),
        ]
        for out, profile in cases:
            with self.subTest(out=out, profile=profile):
                r = self.run_shell("shared_plan", out, profile, data=self.shared_input())
                self.assertNotEqual(r.returncode, 0)

    def test_existing_output_profile_and_profile_symlink_never_overwritten(self):
        output = self.work / "output"
        output.mkdir(); marker = output / "marker"; marker.write_text("keep")
        profile_target = self.work / "target"; profile_target.mkdir()
        profile = self.work / "profile-link"; profile.symlink_to(profile_target, target_is_directory=True)
        r = self.run_shell("shared_plan", output, profile, data=self.shared_input())
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(marker.read_text(), "keep")
        self.assertFalse((profile_target / "token").exists())

    def test_dns_update_rejects_bad_permissions_symlink_and_source_tree_profile(self):
        profile = self.work / "profile"; profile.mkdir(mode=0o700)
        for name, value in (("domain", "slug"), ("token", TOKEN), ("ipv4", "8.8.8.8")):
            (profile / name).write_text(value + "\n"); (profile / name).chmod(0o600)
        (profile / "token").chmod(0o644)
        r = self.run_shell("dns_update", profile, data="YES\n")
        self.assertNotEqual(r.returncode, 0)
        (profile / "token").chmod(0o600); (profile / "token").unlink(); (profile / "token").symlink_to(self.work / "secret")
        (self.work / "secret").write_text(TOKEN + "\n")
        r = self.run_shell("dns_update", profile, data="YES\n")
        self.assertNotEqual(r.returncode, 0)
        r = self.run_shell("dns_update", ROOT / "README.md", data="YES\n")
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
