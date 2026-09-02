# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)

@critical
Feature: Soll-Ist report (planned vs actual)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). Driven on device via flutter_gherkin; every step
  runs the end-to-end device/HTTP path — never a pure-function check.

  The Soll-Ist report screen is not yet landed, so these scenarios are the
  acceptance contract for it and are excluded from the on-device run (each
  Scenario is tagged @pending) until the screen ships. Removing @pending from
  a Scenario promotes it into the default on-device pass (CI gate).

  @pending
  Scenario: Planned vs actual scene counts reconcile
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open the Soll-Ist report for season "1"
    Then I expect the widget "soll-ist-report-screen" to be present within 10 seconds
    And the Soll-Ist report shows planned "12" scenes and actual "10" scenes

  @pending
  Scenario: Moved, missing, skipped and reshot flags are surfaced
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open the Soll-Ist report for season "1"
    Then the Soll-Ist report lists a "moved" scene
    And the Soll-Ist report lists a "missing" scene
    And the Soll-Ist report lists a "skipped" scene
    And the Soll-Ist report lists a "reshot" scene

  @pending
  Scenario: Report becomes final once the shooting day is wrapped
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open the Soll-Ist report for season "1"
    Then the Soll-Ist report is marked final
