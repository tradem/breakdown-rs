<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: Un-pend + run costume_assignment.feature on device (issue #459)

## Problem

Both scenarios in `frontend-flutter/features-spec/costume_assignment.feature`
("Command shows optimistically then reconciles with the projection" and
"Unprivileged caller is denied on the costume stream") still carry the
`@pending` tag, so the on-device `flutter_gherkin` gate (`tool/run_gherkin.sh`,
tagExpression `not @pending`) excludes them. The backend fix for #453 (merged
via #458) shipped the season **repertoire join**: `POST /v1/costumes` accepts
an optional `season_id`, so an **unassigned** costume now renders in the season
stream — the two device gaps G1 (unassigned rows invisible) and G2
(reassign-only, no first assignment) that #368 recorded are closed. The seed
(`seed_http.dart`) already creates the costume via repertoire binding, so c-7
is a genuine FIRST assignment. This change promotes the scenarios into the
on-device pass and aligns the step contract.

## What Changes

- **`features-spec/costume_assignment.feature`:** remove `@pending` from both
  scenarios (they enter the default on-device `not @pending` pass); replace the
  HARNESS STATUS re-pending block with the promotion record; align the denial
  scenario to the real client-side gate (view the costume detail, never an
  assign action that cannot render for a denied membership).
- **`integration_test/gherkin/steps/costume_assignment_steps.dart`:**
  - `I assign costume {string} to character {string}` now targets the
    unassigned-seed contract: the assign button key is
    `assign-costume-<id>-none` (first assignment c-7 → ch-3), not the old
    `assign-costume-<id>-<ch9>` reassignment key.
  - New `I view the costume {string} in the costume stream` step opens the
    costume detail (shared with the assign step) so the viewer-denial scenario
    reaches the `costume-assign-denied` narrative without a button that never
    renders.
  - New `no costume command leaves the device` step asserts the #380 request
    recorder's costume counter is zero — the client-side AUTHZ-GATE (D6) denied
    before any assign/unassign HTTP was issued.
- **`lib/testing/request_recorder.dart`:** add a `costume` counter (paths
  suffixed `/assign` or `/unassign`) and include it in the driver-channel
  snapshot (`total=N;photo=M;costume=K`); reset zeroes it. Backward compatible
  with the existing photo-parser (it builds a map of all `;`-separated pairs).
- **`test/testing/request_recorder_test.dart`:** cover the new costume counter
  and the extended snapshot shape.
- **`features-spec/README.md`:** the general "screens not yet landed → all
  pending" paragraph no longer describes the costume scope (promoted); note the
  promoted state.
- **OpenSpec change artifact** at `openspec/changes/459-costume-assignment-unpend/`.

## Non-goals

- No backend change (the #453 repertoire fix already landed). The stale dev
  backend process must be restarted from the freshly built binary to serve the
  fix, but no source change.
- No change to the `@critical` / `@pending` discipline gates
  (`tool/check_gherkin.sh` already accepts a fully promoted critical scope).
- No change to the app UI — the `assign-costume-<id>-none` keys, `overlay-assign-*`
  and `assigned-*` reconciliation keys already exist and ship.

## Acceptance criteria (from issue #459)

- [x] Promote both scenarios (remove `@pending`); they become part of the
      on-device discipline gate per the app_hook contract.
- [x] Align `costume_assignment_steps.dart` to the unassigned seed contract
      (first assignment c-7 → ch-3; button key transitions
      `assign-costume-<id>-none` on the stream row).
- [x] Unprivileged-denial scenario verified against the real 403 contract:
      the client-side AUTHZ-GATE renders the denial before any network call
      (recorder: zero costume commands left the device).
- [x] On-device run green on the emulator (dev backend, #368 harness): seeds,
      steps, app_hook promotion logic. `bash tool/run_gherkin.sh` → 3 scenarios
      (3 passed: both promoted costume scenarios + the smoke harness probe).
- [x] No `@pending` tag remains on the promoted scenarios.
