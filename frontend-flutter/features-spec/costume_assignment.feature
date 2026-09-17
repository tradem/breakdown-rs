# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)

@critical
Feature: Costume assignment (optimistic update + role denial)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  Covers the CQRS-on-client contract (AGENTS.md §4): a successful command is
  acknowledged immediately (optimistic overlay) and the read projection is
  reconciled afterwards; and the client-side AUTHZ-GATE (D6) that denies the
  assignment on the costume stream for an unprivileged caller.

  HARNESS STATUS after the authoritative on-device run (issue #368): both
  scenarios are RE-PENDING — the run is currently BLOCKED by two REAL
  backend/design gaps the device execution uncovered (this is the value of
  the run, not a harness failure; the harness itself — host-side seeding,
  runtime membership override, id mapping — is in place and was validated
  up to the gaps):

  - G1: the season costume stream (`list_by_season`) JOINs
    `projection_character`, so an UNASSIGNED costume never renders in the
    Kleidung stream — there is NO UI path to a costume's first assignment
    (the app's `assign-costume-<id>-none` row keys are unreachable on the
    real backend; verified on device: stream serves 0 rows).
  - G2: `POST /v1/costumes/{id}/assign` on an assigned costume answers 409
    `costume.already-assigned` (verified against the dev backend), so the
    app's "Reassign" button can never succeed either.

  The optimistic-overlay + reconciliation scenarios (and the denial, which
  needs a rendered stream row) un-pend once the backend decides between
  "season-scoped costumes" and "character-scoped costumes" (tracked as a
  follow-up from #368).

  Harness contract (kept for the un-pending change):
  - `AppHook.onBeforeRun` seeds the REAL dev backend over HTTP
    (`API_BASE`, host-resolved): season → block (block creation
    auto-bootstraps the dev principal as an active costume-dept member in
    dev-auth mode) → characters → costume → server-side pre-assignment.
    The resolved REAL ids are mapped from the symbolic ids (season "1",
    "ch-3", "ch-9", "c-7") via `SeedCache` into `AppWorld.seedIds`.
  - The `I am authenticated as a "{string}" user` step flips the app's
    dev-auth membership override at runtime via the FlutterDriver data
    channel (`dev-membership:role=<role>`) — the runner builds the app once
    with fixed dart-defines, so a per-scenario membership shape cannot be a
    compile-time define. "viewer" yields a capability-less membership: the
    client-side AUTHZ-GATE denies before any network call.

  @pending
  Scenario: Command shows optimistically then reconciles with the projection
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    And the backend is seeded with costume "c-7" and character "ch-3" for season "1"
    When I open the costume assignment for season "1"
    And I assign costume "c-7" to character "ch-3"
    Then the costume assignment appears optimistically
    And the costume assignment projection refreshes

  @pending
  Scenario: Unprivileged caller is denied on the costume stream
    Given the app is launched in dev-auth mode
    And I am authenticated as a "viewer" user
    And the backend is seeded with costume "c-7" and character "ch-3" for season "1"
    When I open the costume assignment for season "1"
    And I assign costume "c-7" to character "ch-3"
    Then the costume stream denies assignment with a denial
