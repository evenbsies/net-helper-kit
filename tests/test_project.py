#!/usr/bin/env python3
"""Offline regression tests. Temporary secrets stay outside the repository."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import struct
import subprocess
import tempfile
import time
import unittest
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parents[1]


def run(*args, data=None, check=True):
    return subprocess.run(args, input=data, text=True, capture_output=True, check=check)


class ProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='nhk-tests-')
        cls.work = Path(cls.tmp.name)
        cls.binary = cls.work / 'hysteria-test-fixture'
        cls.binary.write_text('#!/bin/sh\nprintf "Version: v2.0.0\\n"\n')
        cls.binary.chmod(0o700)
        cls.sha = hashlib.sha256(cls.binary.read_bytes()).hexdigest()
        cls.plan = cls.work / 'plan'
        cls.result = cls.make_plan(cls.plan)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def make_plan(cls, dest, host='node.example.com', internal='24443', external='34443',
                  upstream='1.1.1.1', sha=None, mode='pin', cert=None, key=None,
                  shell=None):
        answers = [host, internal, external, upstream, str(cls.binary), sha or cls.sha, mode]
        if mode == 'cert':
            answers += [str(cert), str(key)]
        cmd = [str(ROOT / 'wizard.sh'), 'plan', str(dest)]
        if shell:
            cmd = shell + cmd
        return run(*cmd, data='\n'.join(answers) + '\n', check=False)

    def lib(self, script):
        return run('sh', '-c', '. "$1/lib/common.sh"; ' + script, 'sh', str(ROOT), check=False)

    def test_01_plan_success(self):
        self.assertEqual(self.result.returncode, 0, self.result.stderr)

    def test_02_client_nat_external_port(self):
        cfg = json.loads((self.plan / 'client.json').read_text())
        self.assertEqual(cfg['server'], 'node.example.com:34443')
        self.assertIn('listen: 0.0.0.0:24443', (self.plan / 'server.yaml').read_text())

    def test_03_pin_required(self):
        cfg = json.loads((self.plan / 'client.json').read_text())
        self.assertTrue(cfg['tls']['insecure'])
        self.assertEqual(len(cfg['tls']['pinSHA256']), 64)
        fingerprint = run('openssl', 'x509', '-in', str(self.plan / 'server.crt'),
                          '-noout', '-fingerprint', '-sha256').stdout.strip().split('=')[1]
        self.assertEqual(cfg['tls']['pinSHA256'], fingerprint.replace(':', '').lower())

    def test_04_uri_and_auth(self):
        cfg = json.loads((self.plan / 'client.json').read_text())
        uri = urlparse((self.plan / 'node-uri.txt').read_text().strip())
        self.assertEqual(uri.username, cfg['auth'])
        self.assertEqual(uri.port, 34443)
        self.assertEqual(parse_qs(uri.query)['pinSHA256'], [cfg['tls']['pinSHA256']])
        self.assertEqual(len(cfg['auth']), 64)
        self.assertIn('password: "' + cfg['auth'] + '"', (self.plan / 'server.yaml').read_text())
        self.assertNotIn(cfg['auth'], self.result.stdout + self.result.stderr)

    def test_05_modes(self):
        self.assertEqual(stat.S_IMODE(self.plan.stat().st_mode), 0o700)
        for file in ['client.json', 'server.key', 'node-uri.txt']:
            self.assertEqual(stat.S_IMODE((self.plan / file).stat().st_mode), 0o600)

    def test_06_manifest(self):
        result = self.lib('verify_plan "' + str(self.plan) + '"')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_07_corruption_rejected(self):
        dest = self.work / 'tampered'
        shutil.copytree(self.plan, dest)
        (dest / 'client.json').write_text('{}')
        self.assertNotEqual(self.lib('verify_plan "' + str(dest) + '"').returncode, 0)

    def test_08_symlink_rejected(self):
        dest = self.work / 'symlink-plan'
        shutil.copytree(self.plan, dest)
        (dest / 'server.key').unlink()
        (dest / 'server.key').symlink_to(self.plan / 'server.key')
        self.assertNotEqual(self.lib('verify_plan "' + str(dest) + '"').returncode, 0)

    def test_09_no_overwrite(self):
        before = (self.plan / 'server.key').read_bytes()
        self.assertNotEqual(self.make_plan(self.plan).returncode, 0)
        self.assertEqual(before, (self.plan / 'server.key').read_bytes())

    def test_10_invalid_inputs(self):
        cases = [dict(host='bad;touch.invalid'), dict(host='a..example'),
                 dict(host='-a.example'), dict(host='999.1.2.3'),
                 dict(internal='53'), dict(internal='5353'), dict(internal='0'),
                 dict(internal='65536'), dict(internal='024443'),
                 dict(external='0'), dict(external='65536'),
                 dict(upstream='127.0.0.1'), dict(upstream='1.2.3.999'),
                 dict(sha='0' * 64), dict(mode='invalid')]
        for i, kwargs in enumerate(cases):
            with self.subTest(kwargs=kwargs):
                dest = self.work / ('invalid-' + str(i))
                self.assertNotEqual(self.make_plan(dest, **kwargs).returncode, 0)
                self.assertFalse(dest.exists())

    def test_11_path_guards(self):
        for path in ['relative', '/tmp/../tmp/plan', '/tmp/plan name', '/']:
            with self.subTest(path=path):
                self.assertNotEqual(self.make_plan(path).returncode, 0)

    def test_12_input_eof_no_artifacts(self):
        dest = self.work / 'eof'
        result = run(str(ROOT / 'wizard.sh'), 'plan', str(dest), data='', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(dest.exists())

    def test_13_rule_validation(self):
        result = run('awk', '-f', str(ROOT / 'lib/rules.awk'),
                     data='# comment\nAds.Example.com\nads.example.com\n', check=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'local=/ads.example.com/\n')
        for value in ['conf-file=/etc/passwd', 'bad..example', '-bad.example', '*.example', '',
                      'local=/bad.example/', 'a' * 64 + '.example']:
            with self.subTest(value=value):
                self.assertNotEqual(run('awk', '-f', str(ROOT / 'lib/rules.awk'),
                                        data=value + '\n', check=False).returncode, 0)

    def test_14_rule_cap(self):
        result = run('awk', '-f', str(ROOT / 'lib/rules.awk'),
                     data=''.join('ad%d.example\n' % n for n in range(5001)), check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_15_busybox_ash(self):
        if not shutil.which('busybox'):
            self.skipTest('busybox is not installed')
        result = self.make_plan(self.work / 'busybox-plan', shell=['busybox', 'sh'])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_16_existing_certificate(self):
        cert = self.work / 'external.crt'
        key = self.work / 'external.key'
        run('openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
            'ec_paramgen_curve:P-256', '-nodes', '-days', '30',
            '-subj', '/CN=node.example.com', '-addext', 'subjectAltName=DNS:node.example.com',
            '-keyout', str(key), '-out', str(cert))
        dest = self.work / 'cert-plan'
        result = self.make_plan(dest, mode='cert', cert=cert, key=key)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads((dest / 'client.json').read_text())['tls']['insecure'])
        result = self.make_plan(self.work / 'bad-cert', host='other.example.com', mode='cert',
                                cert=cert, key=key)
        self.assertNotEqual(result.returncode, 0)
        result = self.make_plan(self.work / 'bad-key', mode='cert', cert=cert,
                                key=self.plan / 'server.key')
        self.assertNotEqual(result.returncode, 0)

    def test_17_loopback_dns_real_process(self):
        binary = shutil.which('dnsmasq')
        if not binary:
            self.skipTest('dnsmasq is not installed')
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        cfg = (self.plan / 'dnsmasq.conf').read_text()
        cfg = cfg.replace('port=5353', 'port=' + str(port))
        cfg = cfg.replace('conf-file=/etc/net-helper-kit/blocklist.conf',
                          'conf-file=' + str(self.plan / 'blocklist.conf'))
        cfg = '\n'.join(line for line in cfg.splitlines()
                        if not line.startswith(('user=', 'group='))) + '\n'
        path = self.work / 'test-dns.conf'
        path.write_text(cfg)
        syntax = run(binary, '--test', '--conf-file=' + str(path), check=False)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        proc = subprocess.Popen([binary, '--keep-in-foreground', '--pid-file=',
                                 '--conf-file=' + str(path)], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.PIPE)
        try:
            time.sleep(0.2)
            self.assertIsNone(proc.poll(), 'dnsmasq exited before query')
            for qtype in [1, 28, 65]:  # A, AAAA, HTTPS: no accidental forwarding
                with self.subTest(qtype=qtype), socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                    sock.settimeout(2)
                    name = b''.join(bytes([len(s)]) + s.encode() for s in
                                    'sub.doubleclick.net'.split('.')) + b'\0'
                    query = struct.pack('!HHHHHH', 1234, 0x0100, 1, 0, 0, 0) + name + struct.pack('!HH', qtype, 1)
                    sock.sendto(query, ('127.0.0.1', port))
                    answer = sock.recv(4096)
                    self.assertEqual(struct.unpack('!H', answer[2:4])[0] & 15, 3)  # NXDOMAIN
        finally:
            proc.terminate()
            proc.wait(timeout=5)
            proc.stderr.close()

    def test_18_public_tree_privacy(self):
        # Generated credentials must never be in the distributable source tree.
        names = {'server.yaml', 'server.key', 'server.crt', 'client.json', 'node-uri.txt', 'hysteria'}
        forbidden = [str(p.relative_to(ROOT)) for p in ROOT.rglob('*')
                     if p.is_file() and '.git' not in p.parts and p.name in names]
        self.assertEqual(forbidden, [])
        for suffix in ['.key', '.pem']:
            self.assertEqual(list(ROOT.rglob('*' + suffix)), [])

    def test_19_healthcheck_rejects_missing_or_wrong_process(self):
        for service in ['nhk-dns', 'nhk-hysteria']:
            for pid in ['', str(os.getpid()), 'not-a-pid']:
                with self.subTest(service=service, pid=pid):
                    result = run('sh', '-c', '. "$1"; service_get_value() { printf "%s" "$TEST_PID"; }; TEST_PID="$2"; healthcheck',
                                 'sh', str(ROOT / 'openrc' / service), pid, check=False)
                    self.assertNotEqual(result.returncode, 0)

    def test_20_healthcheck_accepts_live_application_not_supervisor(self):
        code = 'import ctypes,time; ctypes.CDLL(None).prctl(15,b"hysteria",0,0,0); print("ready",flush=True); time.sleep(10)'
        proc = subprocess.Popen([os.sys.executable, '-c', code], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(proc.stdout.readline().strip(), 'ready')
            result = run('sh', '-c', '. "$1"; service_get_value() { printf "%s" "$TEST_PID"; }; TEST_PID="$2"; healthcheck',
                         'sh', str(ROOT / 'openrc/nhk-hysteria'), str(proc.pid), check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
        finally:
            proc.terminate()
            proc.wait(timeout=5)
            proc.stdout.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
