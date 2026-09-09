// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3 (opencode)
// Co-authored-by: omen-alpha (opencode-go)

@critical
Feature: Soll-Ist report (planned vs actual)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). Driven on device via flutter_gherkin; every step
  runs the end-to-end device/HTTP path — never a pure-function check.

  The Reports screen is landed (`flutter-reports` 2.1): entry is the
  "Reports" action on the day board (`reports-open`), reached after season →
  block → episode → scene → day-board navigation. These scenarios stay
  @pending (excluded from the on-device run via the runner's `not @pending`
  tagExpression) until a seeded on-device backend flow (Phase 2b day
  execution with deterministic Soll/Ist seed data) promotes them — removing
  @pending from a Scenario promotes it into the default on-device pass
  (CI gate).

  @pending
  Scenario: Planned vs actual scene counts reconcile
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I open the reports for shooting day "day-1"
    Then I expect the widget "soll-ist-report-screen" to be present within 10 seconds
    And the Soll-Ist report shows planned "12" scenes and actual "10" scenes

  @pending
  Scenario: Moved, missing, skipped and reshot flags are surfaced
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I open the reports for shooting day "day-1"
    Then the Soll-Ist report lists a "moved" scene
    And the Soll-Ist report lists a "missing" scene
    And the Soll-Ist report lists a "skipped" scene
    And the Soll-Ist report lists a "reshot" scene

  @pending
  Scenario: Report becomes final once the shooting day is wrapped
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I open the reports for shooting day "day-1"
    Then the Soll-Ist report is marked final
