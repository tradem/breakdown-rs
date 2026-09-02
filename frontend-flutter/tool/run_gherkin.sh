#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)
#
# Runs the on-device flutter_gherkin critical-scenario suite against a
# connected device/emulator. This is the authoritative on-device gate for the
# three designated critical flows (AGENTS.md §6, spec flutter-gherkin-hybrid).
# See features-spec/README.md.
#
# Requires a device/emulator to be connected (the runner builds and installs
# the instrumented app and drives it). The DEV_AUTH_SUB / API_BASE values are
# taken from the environment so the suite is not bound to the Android-emulator
# host alias: a physical device or other target supplies a network-reachable
# API endpoint. Defaults match the emulator (10.0.2.2) and the dev dummy
# principal.
set -euo pipefail
cd "$(dirname "$0")/.."
API_BASE="${API_BASE:-http://10.0.2.2:3000}"
DEV_AUTH_SUB="${DEV_AUTH_SUB:-dev-e2e}"
export API_BASE DEV_AUTH_SUB
flutter pub get
dart integration_test/gherkin/gherkin_runner.dart
