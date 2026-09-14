#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# build-release.sh — build the Android release artifacts (prod flavor)
# (OpenSpec change `add-android-release-workflow`, task 3.4; spec
# `flutter-release-artifacts` "APK Split-Per-ABI and AAB Artifacts").
#
# Produces, from the `prod` flavor with the pinned-CA configuration:
#   * three split APKs (--split-per-abi: arm64-v8a, armeabi-v7a, x86_64)
#   * one .aab bundle
# Both signed by the project keystore (signingConfig via environment).
#
# Environment:
#   VERSION_FULL       required — full pubspec version (`X.Y.Z[-pre.N]+N`,
#                      injected as APP_VERSION dart-define)
#   KEYSTORE_FILE / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD
#                      required — signing config (Gradle reads these)
#   OIDC_ISS / OIDC_CLIENT_ID / OIDC_AUDIENCE
#                      required — prod OIDC dart-defines
#
# Exit: 0 = both builds succeeded (Gradle/Flutter failures fail loud).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/release -> frontend-flutter
FLUTTER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$FLUTTER_DIR"

VERSION_FULL="${VERSION_FULL:?VERSION_FULL is required (the full pubspec version)}"
KEYSTORE_FILE="${KEYSTORE_FILE:?KEYSTORE_FILE is required (decoded keystore path — run decode-keystore.sh first)}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:?}"
KEY_ALIAS="${KEY_ALIAS:?}"
KEY_PASSWORD="${KEY_PASSWORD:?}"
OIDC_ISS="${OIDC_ISS:?}"
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:?}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:?}"

flutter build apk --release --flavor prod -t lib/main_prod.dart --split-per-abi \
  --dart-define=APP_VERSION="$VERSION_FULL" \
  --dart-define=OIDC_ISS="$OIDC_ISS" \
  --dart-define=OIDC_CLIENT_ID="$OIDC_CLIENT_ID" \
  --dart-define=OIDC_AUDIENCE="$OIDC_AUDIENCE" \
  --dart-define-from-file=oidc-config.json

flutter build appbundle --release --flavor prod -t lib/main_prod.dart \
  --dart-define=APP_VERSION="$VERSION_FULL" \
  --dart-define=OIDC_ISS="$OIDC_ISS" \
  --dart-define=OIDC_CLIENT_ID="$OIDC_CLIENT_ID" \
  --dart-define=OIDC_AUDIENCE="$OIDC_AUDIENCE" \
  --dart-define-from-file=oidc-config.json

echo "::notice::Split APKs (arm64-v8a, armeabi-v7a, x86_64) and AAB built."
