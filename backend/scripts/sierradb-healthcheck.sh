#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (opencode-go)

# Healthcheck for SierraDB (ADR-015 / ADR-016 / issue #156).
#
# The `tqwewe/sierradb` image ships no `redis-cli` (and no perl), so the RESP3
# endpoint is probed with a raw PING over TCP: SierraDB answers +PONG to a raw
# PING (RESP3 simple string). `bash` (present in the Debian-bookworm base) is
# required for `/dev/tcp`; the historical `redis-cli -3 PING` healthcheck
# never worked because the binary is absent from the image.

set -u

exec 3<>/dev/tcp/127.0.0.1/9090 || exit 1
printf '*1\r\n$4\r\nPING\r\n' >&3 || exit 1
IFS= read -r -t 2 -u 3 reply || exit 1

case "$reply" in
    *PONG*) exit 0 ;;
    *) exit 1 ;;
esac
