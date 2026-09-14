#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# verify-signatures.sh — signature verification for the staged release
# artifacts (OpenSpec change `add-android-release-workflow`, task 3.4;
# spec `flutter-release-signing`, D9 one-key invariant).
#
# Verifies, against the RECORDED project fingerprint (kept in
# docs/release-signing-key-custody.md §2 and mirrored into the workflow):
#   * every staged APK  — apksigner verify --print-certs (apksigner accepts
#     APK files only)
#   * the staged AAB    — jarsigner -verify (same keystore), PLUS a
#     `bundletool build-apks` round-trip signed with the SAME keystore whose
#     generated APKs are re-verified with apksigner against the fingerprint.
#
# The fingerprint gate REFUSES to run while EXPECTED_SHA256_FINGERPRINT is
# unset or 'TBD' — an unbootstrapped pipeline cannot ship unverifiable
# binaries.
#
# Environment:
#   VERSION_NAME                 required — pubspec build-name
#   EXPECTED_SHA256_FINGERPRINT  required — recorded fingerprint (colon-free,
#                                lowercase, 64 hex); 'TBD'/'empty' = refuse
#   KEYSTORE_FILE                required — decoded keystore path
#                                (bundletool round-trip signs with it)
#   KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD   required
#
# Exit: 0 = all artifacts verified, 1 = verification failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/release -> frontend-flutter
FLUTTER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$FLUTTER_DIR"

VERSION_NAME="${VERSION_NAME:?VERSION_NAME is required (the pubspec build-name)}"
EXPECTED="${EXPECTED_SHA256_FINGERPRINT:?}"
KEYSTORE_FILE="${KEYSTORE_FILE:?}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:?}"
KEY_ALIAS="${KEY_ALIAS:?}"
KEY_PASSWORD="${KEY_PASSWORD:?}"

norm() { echo "$1" | tr -d ':' | tr '[:upper:]' '[:lower:]'; }
want="$(norm "$EXPECTED")"

if [ -z "$want" ] || [ "$want" = "tbd" ]; then
  echo "::error::EXPECTED_SHA256_FINGERPRINT is not configured (still 'TBD'). Run the keystore bootstrap (task 1.2) and set the fingerprint per docs/release-signing-key-custody.md §2."
  exit 1
fi

# apksigner lives under ANDROID_HOME (set by GitHub-hosted runners); ANDROID_SDK_ROOT
# is the documented fallback on some setups. Both may be unset locally — that is a
# hard failure (apksigner is required), reported via ::error::, not a crash.
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
BUILD_TOOLS=""
if [ -n "$SDK_ROOT" ]; then
  BUILD_TOOLS="$(ls -d "$SDK_ROOT"/build-tools/* 2>/dev/null | sort -V | tail -n 1)"
fi
if [ -z "$BUILD_TOOLS" ]; then
  echo "::error::No Android build-tools found (ANDROID_HOME='${SDK_ROOT:-unset}') — apksigner is required for APK verification."
  exit 1
fi
APKSIGNER="$BUILD_TOOLS/apksigner"

# --- APKs -------------------------------------------------------------------
"$APKSIGNER" verify --print-certs "dist/breakdown-$VERSION_NAME-arm64-v8a.apk" 2>/dev/null
for apk in dist/breakdown-*.apk; do
  cert="$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
    | sed -n 's/.*certificate SHA-256 digest: //p' | head -n 1)"
  if [ -z "$cert" ]; then
    echo "::error::$apk could not be verified (no SHA-256 digest reported)."
    exit 1
  fi
  got="$(norm "$cert")"
  if [ "$got" != "$want" ]; then
    echo "::error::$apk was signed with fingerprint '$got' — does NOT match the recorded project fingerprint '$want' (D9 one-key invariant)."
    exit 1
  fi
done
echo "::notice::All split APKs carry the recorded project fingerprint ($want)."

# --- AAB: certificate fingerprint + jarsigner + bundletool round-trip ------
# The staged AAB must carry the project key itself: jarsigner -verify only
# proves a valid signature, not WHO signed. Compare its signer fingerprint
# (keytool -printcert -jarfile) to the recorded one BEFORE the bundletool
# round-trip — the round-trip re-signs with KEYSTORE_FILE, so it can never
# prove the staged AAB's origin.
aab_cert="$(keytool -printcert -jarfile "dist/breakdown-$VERSION_NAME.aab" 2>/dev/null \
  | sed -n 's/.*SHA256: //p' | head -n 1)"
if [ -z "$aab_cert" ]; then
  echo "::error::staged AAB (dist/breakdown-$VERSION_NAME.aab) could not be verified via keytool -printcert -jarfile (no SHA-256 digest reported)."
  exit 1
fi
got_aab="$(norm "$aab_cert")"
if [ "$got_aab" != "$want" ]; then
  echo "::error::staged AAB was signed with fingerprint '$got_aab' — does NOT match the recorded project fingerprint '$want' (D9 one-key invariant)."
  exit 1
fi
# jarsigner verifies the AAB structural integrity (apksigner accepts APK
# files only).
jarsigner -verify -verbose:summary "dist/breakdown-$VERSION_NAME.aab" >/dev/null
echo "::notice::AAB signed with the recorded project fingerprint and passes jarsigner -verify."

# bundletool round-trip: build APKs from the AAB with the SAME keystore,
# then re-verify every generated APK with apksigner. The JAR is
# checksum-pinned (CI hardening: pinned binaries discipline).
BUNDLETOOL_SHA256=675786493983787ffa11550bdb7c0715679a44e1643f3ff980a529e9c822595c
BT_TMP="${RUNNER_TEMP:-$(mktemp -d)}"
curl -fsSL -o "$BT_TMP/bundletool.jar" \
  "https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar"
echo "$BUNDLETOOL_SHA256  $BT_TMP/bundletool.jar" | sha256sum -c -
java -jar "$BT_TMP/bundletool.jar" build-apks \
  --bundle="dist/breakdown-$VERSION_NAME.aab" \
  --output="$BT_TMP/roundtrip.apks" \
  --ks="$KEYSTORE_FILE" \
  --ks-key-alias="$KEY_ALIAS" \
  --ks-pass=pass:"$KEYSTORE_PASSWORD" \
  --key-pass=pass:"$KEY_PASSWORD" \
  --overwrite
mkdir -p "$BT_TMP/roundtrip"
unzip -q -o "$BT_TMP/roundtrip.apks" -d "$BT_TMP/roundtrip"

found=0
while IFS= read -r -d '' apk; do
  found=$((found + 1))
  cert="$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
    | sed -n 's/.*certificate SHA-256 digest: //p' | head -n 1)"
  got="$(norm "$cert")"
  if [ "$got" != "$want" ]; then
    echo "::error::bundletool round-trip APK $apk does not carry the recorded project fingerprint."
    exit 1
  fi
done < <(find "$BT_TMP/roundtrip" -name '*.apk' -print0)
if [ "$found" -eq 0 ]; then
  echo "::error::bundletool build-apks produced no APKs to verify."
  exit 1
fi
echo "::notice::bundletool round-trip verified $found APK(s) with the recorded project fingerprint ($want)."
