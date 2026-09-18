# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)
# Co-authored-by: deepseek-v4-flash (neuralwatt)

@critical
Feature: Costume assignment (optimistic update + role denial)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  Covers the CQRS-on-client contract (AGENTS.md §4): a successful command is
  acknowledged immediately (optimistic overlay) and the read projection is
  reconciled afterwards; and the client-side AUTHZ-GATE (D6) that denies the
  assignment on the costume stream for an unprivileged caller.

  HARNESS STATUS (promoted, issue #459): the two device gaps recorded by the
  #368 on-device run are closed by the backend repertoire fix (issue #453,
  merged via #458) and the scenarios below are PROMOTED into the default
  on-device pass — neither carries `@pending`, so the runner's
  `not @pending` tagExpression runs them against the real dev backend:

  - G1 (closed): the season costume stream (`list_by_season`) now returns the
    union of assigned-to-season-character OR in-repertoire costumes
    (`projection_costume_season` join), so an UNASSIGNED costume seeded with
    `POST /v1/costumes {season_id}` renders in the Kleidung stream — the
    app's `assign-costume-<id>-none` first-assignment row key is reachable.
  - G2 (closed): with the seed costume UNASSIGNED, the scenario exercises a
    genuine FIRST assignment (c-7 → ch-3) instead of the reassign path that
    409'd `costume.already-assigned`. The `assign-costume-<id>-none` button
    key is the first-assignment entry; the picker submit carries the picked
    character + the acted-on row's version.

  Harness contract:
  - `AppHook.onBeforeRun` seeds the REAL dev backend over HTTP
    (`API_BASE`, host-resolved): season → block (block creation
    auto-bootstraps the dev principal as an active costume-dept member in
    dev-auth mode) → characters → costume (repertoire season binding, UNASSIGNED;
    issue #453) → server-side pre-assignment is REMOVED — the seed leaves c-7
    unassigned on purpose so the scenario exercises THE first assignment. The
    resolved REAL ids are mapped from the symbolic ids (season "1",
    "ch-3", "ch-9", "c-7") via `SeedCache` into `AppWorld.seedIds`.
  - The `I am authenticated as a "{string}" user` step flips the app's
    dev-auth membership override at runtime via the FlutterDriver data
    channel (`dev-membership:role=<role>`) — the runner builds the app once
    with fixed dart-defines, so a per-scenario membership shape cannot be a
    compile-time define. "viewer" yields a capability-less membership: the
    client-side AUTHZ-GATE denies any costume command before that command's
    network call (read-model/detail traffic stays allowed). The denial
    scenario therefore OPENS the costume detail (the `costume-assign-denied`
    narrative renders in place of the assign button) and asserts the #380
    request recorder proves zero costume command traffic left the device.

  Scenario: Command shows optimistically then reconciles with the projection
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    And the backend is seeded with costume "c-7" and character "ch-3" for season "1"
    When I open the costume assignment for season "1"
    And I assign costume "c-7" to character "ch-3"
    Then the costume assignment appears optimistically
    And the costume assignment projection refreshes

  Scenario: Unprivileged caller is denied on the costume stream
    Given the app is launched in dev-auth mode
    And I am authenticated as a "viewer" user
    And the backend is seeded with costume "c-7" and character "ch-3" for season "1"
    When I open the costume assignment for season "1"
    And I view the costume "c-7" in the costume stream
    Then the costume stream denies assignment with a denial
    And no costume command leaves the device
