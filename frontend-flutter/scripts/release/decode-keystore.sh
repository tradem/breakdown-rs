#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# decode-keystore.sh — decode the release keystore from CI secret material
# (OpenSpec change `add-android-release-workflow`, task 1.2; spec
# `flutter-release-signing` — signing material flows through environment
# secrets, never the tree).
#
# Steps:
#   1. Strip paste artifacts (whitespace/newlines/quotes) — GNU base64 -d
#      fails on \r and stray quotes with 'invalid input'.
#   2. Classify leftover garbage WITHOUT leaking secret values: report only
#      the count/shape of non-base64 characters (e.g. PEM headers,
#      line continuations).
#   3. Strict-decode and sanity-check the decoded size.
#
# The decoded file lands under ${RUNNER_TEMP:-/tmp}/keystore/release.keystore;
# when GITHUB_OUTPUT is set the path is emitted as output `keystore_path`
# for downstream steps.
#
# Environment:
#   KEYSTORE_BASE64   required — base64-wrapped keystore (pure 'base64 -w0'
#                     output: no PEM headers, no quotes, no continuations)
set -euo pipefail

KEYSTORE_BASE64="${KEYSTORE_BASE64:?KEYSTORE_BASE64 is not set — run the keystore bootstrap first (docs/release-signing-key-custody.md, task 1.2)}"

keystore_dir="${RUNNER_TEMP:-/tmp}/keystore"
mkdir -p "$keystore_dir"
out_file="$keystore_dir/release.keystore"

# 1. strip paste artifacts
cleaned="$(printf '%s' "$KEYSTORE_BASE64" | tr -d ' \t\r\n"')"
if [ -z "$cleaned" ]; then
  echo "::error::KEYSTORE_BASE64 is empty after stripping whitespace — the secret was not populated."
  exit 1
fi

# 2. garbage classification (no values logged, only shapes/counts)
junk="$(printf '%s' "$cleaned" | tr -d 'A-Za-z0-9+/=' | head -c 40)"
if [ -n "$junk" ]; then
  classes="$(printf '%s' "$junk" | fold -w1 | sort -u | sed 's/^-/<dash>/; s/^ /<space>/')"
  echo "::error::KEYSTORE_BASE64 contains non-base64 characters (count: $(printf '%s' "$junk" | wc -c); classes: ${classes}). The secret must be the PURE output of 'base64 -w0 <keystore-file>' — no PEM headers (-----BEGIN...), no line continuations, no quotes. Tip: set it directly via 'base64 -w0 <keystore> | gh secret set KEYSTORE_BASE64 --env Release -R <owner>/<repo>' to avoid clipboard artifacts."
  exit 1
fi

# 3. strict decode + size sanity check
printf '%s' "$cleaned" | base64 -d > "$out_file"
if [ "$(wc -c < "$out_file")" -lt 100 ]; then
  echo "::error::Decoded keystore is suspiciously small ($(wc -c < "$out_file") bytes) — KEYSTORE_BASE64 does not look like a keystore. Re-create the secret with 'base64 -w0 <file>' output only."
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "keystore_path=$out_file" >> "$GITHUB_OUTPUT"
fi
echo "::notice::Keystore decoded to $out_file ($(wc -c < "$out_file") bytes)."
