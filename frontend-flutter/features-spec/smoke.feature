# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)

@smoke
Feature: App launches on device
  Harness-proof scenario: exercises the built-in flutter_gherkin step against
  the already-landed SeasonsScreen plus one custom Given step that resolves
  the dev-auth gate (Continue as dev-e2e on the `login-continue-button`
  key; the app boots signed out at the auth gate per spec
  `flutter-auth-shell`), proving the harness (instrumented app + driver +
  feature parsing) works end-to-end on a device/emulator. Intentionally
  NOT tagged @pending, so it always runs in the default on-device pass.

  Scenario: Home screen renders the seasons list
    Given the app is launched in dev-auth mode
    Then I expect the widget "seasons-list" to be present within 30 seconds
