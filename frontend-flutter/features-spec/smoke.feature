# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)

@smoke
Feature: App launches on device
  Harness-proof scenario. It exercises ONLY built-in flutter_gherkin steps
  (no custom step definitions) against the already-landed SeasonsScreen, so
  the on-device flutter_gherkin runner has at least one green scenario that
  proves the harness (instrumented app + driver + feature parsing) works
  end-to-end on a device/emulator. It is intentionally NOT tagged @pending,
  so it always runs in the default on-device pass.

  Scenario: Home screen renders the seasons list
    Then I expect the widget "seasons-list" to be present within 30 seconds
