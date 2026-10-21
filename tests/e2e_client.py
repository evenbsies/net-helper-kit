#!/usr/bin/env python3
"""Opt-in loopback test against a disposable installed server, never a user's VPS.
Usage: python3 tests/e2e_client.py /trusted/hysteria /private/client.json
Requires curl, a server endpoint on 127.0.0.1, and the default doubleclick.net rule.
"""
import http.server
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'nhk-loopback-ok')

    def log_message(self, *args):
        pass


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    binary, config_path = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads(config_path.read_text())
    if not cfg['server'].startswith('127.0.0.1:'):
        raise SystemExit('Refusing non-loopback target; only disposable local servers are supported')
    if len(cfg.get('tls', {}).get('pinSHA256', '')) != 64:
        raise SystemExit('A pinned certificate is required for this test')
    port = free_port()
    cfg['socks5'] = {'listen': '127.0.0.1:' + str(port)}
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    with tempfile.TemporaryDirectory(prefix='nhk-e2e-') as directory:
        directory = Path(directory)
        path = directory / 'client.json'
        path.write_text(json.dumps(cfg))
        path.chmod(0o600)
        with (directory / 'client.log').open('wb') as log:
            proc = subprocess.Popen([str(binary), 'client', '--config', str(path)],
                                    stdout=log, stderr=log)
            try:
                ready = False
                for _ in range(50):
                    if proc.poll() is not None:
                        break
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=.1):
                            ready = True
                            break
                    except OSError:
                        time.sleep(.1)
                assert ready, 'Pinned official client did not start'
                proxy = '127.0.0.1:' + str(port)
                allowed = subprocess.run(['curl', '--noproxy', '', '--silent', '--show-error',
                                          '--max-time', '5', '--socks5-hostname', proxy,
                                          'http://127.0.0.1:' + str(httpd.server_port)],
                                         capture_output=True)
                assert allowed.returncode == 0 and allowed.stdout == b'nhk-loopback-ok', 'Proxy request failed'
                print('PASS: official Hysteria client + pinned TLS + SOCKS5 loopback HTTP')
                blocked = subprocess.run(['curl', '--noproxy', '', '--silent', '--show-error',
                                          '--max-time', '5', '--socks5-hostname', proxy,
                                          'http://sub.doubleclick.net/'], capture_output=True)
                assert blocked.returncode == 97, 'Expected SOCKS5 rejection of blocked domain, not a timeout'
                print('PASS: domain sent through SOCKS5 is rejected by server-side DNS')
            finally:
                proc.terminate()
                proc.wait(timeout=5)
        cfg['tls']['pinSHA256'] = '0' * 64
        path.write_text(json.dumps(cfg))
        with (directory / 'bad-pin.log').open('wb') as log:
            bad = subprocess.Popen([str(binary), 'client', '--config', str(path)], stdout=log, stderr=log)
            try:
                code = bad.wait(timeout=8)
                assert code != 0, 'Wrong certificate pin was accepted'
                diagnostic = (directory / 'bad-pin.log').read_bytes().lower()
                assert b'pinned hash' in diagnostic or b'fingerprint' in diagnostic, 'Failure was not a fingerprint rejection'
                print('PASS: wrong TLS fingerprint is rejected')
            finally:
                if bad.poll() is None:
                    bad.terminate()
                    bad.wait(timeout=5)
    httpd.shutdown()
    httpd.server_close()


if __name__ == '__main__':
    main()
