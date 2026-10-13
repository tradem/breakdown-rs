#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (neuralwatt)
#
# Linker wrapper for local builds (issue #631).
#
# rustc invokes this in place of the system C compiler. We deliberately keep
# the C compiler as the link *driver* (rather than calling ld.lld directly)
# and only ask it to use a faster linker, so all of the driver's implicit
# flags — crt startup files, `-lgcc_s`, library search paths — keep working.
#
# Preference order: mold → lld → the driver's default linker. Machines with
# neither mold nor lld therefore build exactly as before. Override the
# driver with `CC` (e.g. `CC=clang`) if needed.

set -euo pipefail

cc="${CC:-cc}"

if command -v mold >/dev/null 2>&1; then
    exec "$cc" -fuse-ld=mold "$@"
fi

if command -v ld.lld >/dev/null 2>&1 || command -v lld >/dev/null 2>&1; then
    exec "$cc" -fuse-ld=lld "$@"
fi

exec "$cc" "$@"
