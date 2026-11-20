#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
cd "$(dirname "$0")/.."
# A && B || die guards intentionally reject if either condition fails.
shellcheck -x -e SC2015 setup.sh wizard.sh lib/*.sh tests/*.sh
shellcheck -s sh -e SC2034 openrc/*
for file in setup.sh wizard.sh lib/*.sh openrc/* tests/*.sh; do sh -n "$file"; done
bash -n vendor/hysteria/install_server.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
