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
# supplied by the runner config (integration_test/gherkin/configuration.dart),
# not hardcoded here.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
dart integration_test/gherkin/gherkin_runner.dart
