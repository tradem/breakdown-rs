# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)
# Co-authored-by: glm-5.3 (neuralwatt)

@critical
Feature: Season setup wizard (guided production setup)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  Covers the linear wizard contract (spec flutter-season-setup-wizard):
  smart defaults, sequential dispatch with per-command reconciliation
  (ids sourced exclusively from command responses — CQRS boundary),
  destructive abort with confirmation (team decision 3), and partial
  failure with in-session retry.

  The step definitions ship with this change; the scenarios were
  PROMOTED to the on-device acceptance pass: the @pending tag was
  removed after the first on-device validation (the underlying
  flows ran green against the dev backend in
  integration_test/season_setup_wizard_test.dart).

  RE-PENDING (issue #368 follow-up): the #369/#368 on-device rerun hit a
  series-scoped block-number 409 — the wizard happy path needs its own
  harness repair against accumulated dev-series state (derive walks the
  boot-time seasons cache while seeding runs concurrently). RECOVERY
  (issue #455): `seedDerivedNumbers` now derives from LIVE per-season
  block fetches (handling the accumulated series), and the episode base
  is re-derived after the first block create (episodes are BlockMember-
  scoped, so the wizard can only read them once it owns a block). The
  happy path below ran green on-device against the accumulated dev
  series and is PROMOTED.

  The three sibling scenarios below remain @pending: they were never
  on-device validated (the #368 run aborted at the happy path's 409)
  and their first on-device passes exposed independent pre-existing
  harness gaps OUTSIDE the #455 derive repair — the template scenario's
  blocks-step draft-card finder, the abort scenario's empty-state
  assertion vs accumulated data, and the partial-failure scenario's
  fault-interaction — tracked in a follow-up issue.

  Scenario: Happy path creates the season, blocks, and episodes
    Given the app is launched in dev-auth mode
    And I am authenticated as a "planner" user
    When I start the season setup wizard from the empty state
    Then the season number defaults to the highest existing plus one
    When I set the season number to "1" and the name "Sommer 2026"
    And I advance to the blocks step
    And I apply the template "4x8"
    And I advance to the review step
    Then the review shows "Season 1 · Sommer 2026" with 4 blocks and 32 episodes
    When I confirm the review
    Then the wizard shows the created structure "5 Blöcke · 40 Episoden"
    And the AI import offer depends on the existing AI configuration

  @pending
  Scenario: Template application expands editable drafts
    Given the app is launched in dev-auth mode
    And I am authenticated as a "planner" user
    When I start the season setup wizard from the empty state
    And I advance to the blocks step
    And I apply the template "3x6"
    Then three block drafts with 6 episodes each exist and stay editable
    When I remove the first block draft
    Then the draft list updates and the wizard stays on the blocks step

  @pending
  Scenario: Partial failure stops the dispatch and offers in-session retry
    Given the app is launched in dev-auth mode
    And I am authenticated as a "planner" user
    And the backend rejects the first block create with a conflict
    When I complete the season setup with 2 blocks of 4 episodes
    Then the wizard stops with the created-so-far summary
    And the conflict is reported keyed on its problem code
    When I retry the remaining commands
    Then the wizard reaches the completion screen with the full structure

  @pending
  Scenario: Abort discards the drafts after an explicit confirmation
    Given the app is launched in dev-auth mode
    And I am authenticated as a "planner" user
    When I start the season setup wizard from the empty state
    And I enter a season name
    And I leave the wizard without submitting
    Then the discard confirmation names what will be lost
    When I confirm the discard
    Then nothing was created and reopening starts fresh
