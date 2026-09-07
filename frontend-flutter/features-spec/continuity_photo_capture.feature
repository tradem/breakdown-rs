# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: muse-spark (pi)

@critical
Feature: Continuity photo capture (AUTHZ-GATE to thumb)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  Exercises BOTH authorization gates (AGENTS.md §5, D6) as SEPARATE scenarios
  so each is proven independently:
    - the client-side AUTHZ-GATE preflight (currentMembershipProvider,
      capability `upload_continuity_photos`) refuses BEFORE any network call
      leaves the device (Scenario: client preflight); and
    - the server-side handler gate (SeasonPhotoAccessPolicy) rejects a request
      that does reach it (Scenario: server gate).
  Then the happy path: capture → prepare → raw-bytes upload → link →
  projector-lag reconciliation → strip count moves (Scenario: upload
  reconciles). And the bounded-watch expiry: a variant stuck in Processing
  past the budget stops polling with recovery affordances intact
  (Scenario: watch expires).

  Seed preconditions (dev-auth mode, 4.1 emulator seed): season "1" with
  block "b-1", episode "e-1", scene "s-1" scheduled on shooting day "day-1"
  with scene shoot "ssh-1", and costume "c-1". The server-gate scenario
  additionally seeds a link denial for "ssh-1"; the watch-expired scenario
  seeds a continuity photo whose variants stay Processing past the
  60-second watch budget.

  Scenario: Client-side AUTHZ-GATE refuses capture before any network call
    Given the app is launched in dev-auth mode
    And I am authenticated as a "viewer" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    Then the continuity denial narrative appears
    And no network request leaves the device

  Scenario: Server-side handler rejects an unauthorized link
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I pick costume "c-1" for the continuity capture of scene shoot "ssh-1"
    And I capture a continuity photo for scene shoot "ssh-1"
    And I accept the capture rationale
    Then the day board shows the command denial

  Scenario: Upload reconciles through projector lag to the strip
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    And I pick costume "c-1" for the continuity capture of scene shoot "ssh-1"
    And I capture a continuity photo for scene shoot "ssh-1"
    And I accept the capture rationale
    Then the continuity count for "ssh-1" becomes "Continuity (1)"

  Scenario: Watch expires while a variant is still Processing
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open season "1"
    And I open block "b-1"
    And I open episode "e-1"
    And I open scene "s-1"
    And I open the day board for shooting day "day-1"
    Then the continuity strip for "ssh-1" shows processing
    When 75 seconds pass so the watch budget expires
    Then the continuity strip for "ssh-1" still shows processing
    And the capture affordance for "ssh-1" remains
