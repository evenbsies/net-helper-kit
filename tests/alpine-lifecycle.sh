#!/bin/sh
# SPDX-License-Identifier: MIT
# Only run INSIDE a disposable Alpine root, never on a VPS or normal OS.
set -eu
umask 077
[ "${NHK_DISPOSABLE_ROOT:-}" = YES ] && [ -f /.nhk-disposable-test-root ] || {
    printf '%s\n' 'Refusing: requires an explicitly marked disposable Alpine test root' >&2
    exit 1
}
[ "$#" -eq 1 ] || { echo 'Usage: alpine-lifecycle.sh /private/plan' >&2; exit 1; }
BASE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=lib/common.sh
. "$BASE/lib/common.sh"
need_root_alpine
verify_plan "$1"
[ ! -e /etc/net-helper-kit ] || die 'Use a fresh test root'
TEST_PLAN=$1
WORK=$(mktemp -d /tmp/nhk-lifecycle.XXXXXX)
# WORK contains private test credentials; intentionally retain it for local review.
printf 'YES\n' | "$BASE/wizard.sh" apply "$TEST_PLAN"
"$BASE/wizard.sh" status
before=$(sha_file /etc/net-helper-kit/server.key)
if printf 'YES\n' | "$BASE/wizard.sh" apply "$TEST_PLAN" > "$WORK/second-install.log" 2>&1; then
    die 'Repeated install was not rejected'
fi
[ "$before" = "$(sha_file /etc/net-helper-kit/server.key)" ] || die 'Existing key changed'
[ "$(id -u nhk)" -ne 0 ] || die 'Proxy ran as root'
[ "$(id -u nhk-dns)" -ne 0 ] || die 'DNS ran as root'
printf 'YES\n' | "$BASE/wizard.sh" uninstall
[ -f /etc/net-helper-kit/client.json ] || die 'Uninstall deleted private configuration'
[ ! -e /opt/net-helper-kit ] || die 'Binary directory survived uninstall'
[ ! -e /etc/init.d/nhk-hysteria ] || die 'Service script survived uninstall'
mv /etc/net-helper-kit "$WORK/preserved-configuration"
# These are dedicated test accounts created moments ago, in a marked scratch root.
deluser nhk; deluser nhk-dns
delgroup nhk 2>/dev/null || :
delgroup nhk-dns 2>/dev/null || :
cp -R "$TEST_PLAN" "$WORK/bad-plan"
printf '\ninvalid yaml: [\n' >> "$WORK/bad-plan/server.yaml"
(cd "$WORK/bad-plan" && for item in $PLAN_FILES; do sha256sum "$item"; done) > "$WORK/bad-plan/SHA256SUMS"
if printf 'YES\n' | "$BASE/wizard.sh" apply "$WORK/bad-plan" > "$WORK/rollback.log" 2>&1; then
    die 'Broken server config was reported as healthy'
fi
grep -q 'Hysteria 应用进程未就绪' "$WORK/rollback.log" || die 'Failure occurred for an unexpected reason'
[ ! -e /etc/net-helper-kit ] || die 'Rollback left configuration directory'
[ ! -e /opt/net-helper-kit ] || die 'Rollback left binary directory'
[ ! -e /etc/init.d/nhk-hysteria ] || die 'Rollback left proxy service'
[ ! -e /etc/init.d/nhk-dns ] || die 'Rollback left DNS service'
printf 'PASS: install/status/overwrite refusal/uninstall/data retention/failure rollback\nPrivate scratch test logs: %s\n' "$WORK"
