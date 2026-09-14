#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# stage-artifacts.sh — rename built Android artifacts to release names
# (OpenSpec change `add-android-release-workflow`, task 3.4; spec
# `flutter-release-artifacts` "APK Split-Per-ABI and AAB Artifacts").
#
# Renames the Gradle/Flutter outputs into the explicit, greppable release
# names (`breakdown-<version>-<abi>.apk` / `breakdown-<version>.aab`) in
# frontend-flutter/dist/:
#   build/app/outputs/flutter-apk/app-<abi>-prod-release.apk
#   build/app/outputs/bundle/prodRelease/app-prod-release.aab
#
# Environment:
#   VERSION_NAME    required — pubspec build-name (e.g. 1.2.0-alpha.1)
#
# Exit: 0 = artifacts staged, 1 = missing build output (fail loud).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/release -> frontend-flutter
FLUTTER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$FLUTTER_DIR"

VERSION_NAME="${VERSION_NAME:?VERSION_NAME is required (the pubspec build-name)}"

APK_DIR="build/app/outputs/flutter-apk"
AAB="build/app/outputs/bundle/prodRelease/app-prod-release.aab"

mkdir -p dist
missing=""
for abi in arm64-v8a armeabi-v7a x86_64; do
  src="$APK_DIR/app-$abi-prod-release.apk"
  if [ ! -f "$src" ]; then
    missing="$missing $src"
    continue
  fi
  mv "$src" "dist/breakdown-$VERSION_NAME-$abi.apk"
done
if [ ! -f "$AAB" ]; then
  missing="$missing $AAB"
fi
if [ -n "$missing" ]; then
  echo "::error::Expected build outputs are missing:$missing — did both `flutter build apk --release --flavor prod -t lib/main_prod.dart --split-per-abi` and `flutter build appbundle --release --flavor prod -t lib/main_prod.dart` succeed?"
  exit 1
fi
mv "$AAB" "dist/breakdown-$VERSION_NAME.aab"
ls -la dist
