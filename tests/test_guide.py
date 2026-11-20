#!/usr/bin/env python3
"""Offline command routing and naming checks; no provider requests."""
from pathlib import Path
import os
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GuideTests(unittest.TestCase):
    def wizard(self, *args, data=None):
        return subprocess.run([str(ROOT / 'wizard.sh'), *args], input=data,
                              text=True, capture_output=True, timeout=5)

    def test_default_opens_menu(self):
        result = self.wizard(data='4\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('net-helper-kit 分步向导', result.stdout)
        self.assertIn('shared-plan', result.stdout)

    def test_help_does_not_request_input(self):
        result = self.wizard('--help', data='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Hysteria 2', result.stdout)
        self.assertIn('首次登录和选名', result.stdout)

    def test_invalid_menu_choice_stops(self):
        result = self.wizard('guide', data='invalid\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('未执行任何操作', result.stderr)

    def test_shared_commands_require_paths(self):
        for command in ['shared-plan', 'dns-update']:
            result = self.wizard(command, data='')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('用法', result.stderr)

    def test_private_host_passed_to_plan_cannot_be_changed_by_input(self):
        # Stop at invalid port before any output/keys are generated. The first
        # input must be consumed as a port, not as a second server hostname.
        script = '. "$1/lib/common.sh"; . "$1/lib/plan.sh"; BASE=$1; NHK_HOST_DEFAULT=fixture.duckdns.org; plan /tmp/nhk-uncreated-guide-check'
        result = subprocess.run(['sh', '-eu', '-c', script, 'sh', str(ROOT)],
                                input='bad-port\n', text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('使用共享域名: fixture.duckdns.org', result.stdout)
        self.assertNotIn('服务器公网 IPv4 或域名（不自动探测）', result.stderr)
        self.assertIn('内部端口', result.stderr)

    def test_satisfied_install_dependencies_do_not_reload_repositories(self):
        script = '. "$1/lib/install.sh"; apk() { [ "$1" = info ]; }; ensure_install_packages dnsmasq openssl'
        result = subprocess.run(['sh', '-eu', '-c', script, 'sh', str(ROOT)],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_install_snapshot_does_not_use_tmpfs_default(self):
        script = (ROOT / 'lib/install.sh').read_text()
        self.assertIn('mktemp -d /var/lib/.nhk-apply.XXXXXX', script)
        self.assertNotIn('mktemp -d /tmp/nhk-apply.', script)

    def test_neutral_service_paths_are_consistent(self):
        for name in ['nhk-dns', 'nhk-hysteria']:
            path = ROOT / 'openrc' / name
            self.assertTrue(path.is_file())
            self.assertTrue(os.access(path, os.X_OK))
            self.assertIn('/etc/net-helper-kit', path.read_text())
        for path in [ROOT / 'wizard.sh', *list((ROOT / 'lib').glob('*.sh'))]:
            self.assertNotIn('/etc/hy2-dns-wizard', path.read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
