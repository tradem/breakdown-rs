# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: muse-spark (pi)

@critical
Feature: Soll-Ist execution (plan to wrap)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  The costume department's on-set loop on the day board: plan the Soll,
  execute the Ist (start, actual-order rearrange, finish, skip), and wrap
  the day into read-only finality. Ist state (statuses, actual order,
  `final` from `wrapped_at`) renders from the read model only — the client
  never derives it (spec `flutter-scene-shoots-screen`, D2).

  Seed preconditions (dev-auth mode, 4.1 emulator seed): season "1" with
  block "b-1", episode "e-1", scenes "s-1" and "s-2"; shooting day "day-1"
  with scene shoots "ssh-1" (scene "s-1", planned_order "a0") and "ssh-2"
  (scene "s-2", planned_order "a1"), both Planned; empty shooting day
  "day-2" with scene "s-1" scheduled on it.

  Scenario: Plan a shoot on an empty day
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-2"
    And I plan the first shoot
    Then the board shows a "Planned" shoot

  Scenario: Execute the day from plan to finish with a skip
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I start scene shoot "ssh-1"
    Then the board shows a "In progress" shoot
    When I set the actual order of scene shoot "ssh-2" to "a0!"
    Then the order of scene shoot "ssh-2" reads "Actual a0! (planned a1)"
    When I finish scene shoot "ssh-1"
    And I skip scene shoot "ssh-2"
    Then the board shows a "Shot" shoot
    And the board shows a "Skipped" shoot

  Scenario: Wrap makes the day final and read-only
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I wrap the shooting day
    Then the day board shows finality
    And no actions remain for scene shoot "ssh-1"
