<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: Costume Reassign — client-side unassign→assign sequence (issue #454)

## Problem

`POST /v1/costumes/{id}/assign` on a costume that `character_id != NULL`
answers **409 `costume.already-assigned`** (backend domain rule, verified
against the dev backend). The app's `_AssignmentSection` renders a
**"Reassign"** button (`assign-costume-<id>-<currentCharacterId>`) whenever
`character_id != null` and dispatches the same assign command — it therefore
always fails. The backend only accepts the plain assign command for a
genuinely UNASSIGNED costume; assigning to a different character and
re-assigning to the same character (422) are both rejected.

The #368-on-device-gates ship (#453 backend repertoire fix + #459 unpend)
worked around the bug by seeding the on-device costume UNASSIGNED so the
critical scenario exercises a first assignment only — the Reassign path was
never covered by any test tier, leaving the bug live.

The issue's decision (AC-1) is made: **client-side unassign→assign sequence
with fence-friendly version echoes** (chosen over a backend reassign semantic;
the user confirmed this approach).

## What Changes

- **`lib/features/costumes/costumes_controller.dart`** — `CostumesController.assign`
  now branches:
  - **No-op** when the costume is already bound to the *picked* character
    (the backend 422s the same-character reassign command; the assignment the
    caller asked for already holds).
  - **Reassignment** when bound to a *different* character: a client-side
    `unassign→assign` sequence — `unassign` echoes the acted-on row's
    version; the follow-up `assign` echoes the **unassign ACK** version
    (never the pre-command version). A single bounded reconcile pass runs
    after the final ack; the intermediate unassigned overlay is replaced by
    the final assigned overlay (the honest intermediate state still renders
    briefly — the sequence is not atomic).
  - **Failure semantics (no silent discard, AGENTS.md §4):** an assign-leg
    failure after a successful unassign leaves the costume genuinely
    UNASSIGNED — the overlay shows that true state and the failure surfaces
    via `costumesCommandErrorProvider` (`_InlineError` keyed on the stable
    `code`).
  - First-assignment path is unchanged.
  - `// AUTHZ-GATE:` comment retained on the public `assign` entry (both
    legs are covered by the single `_assignGate()` check before any network
    call).
- **`test/features/costumes/costume_detail_screen_test.dart`** — three new
  widget tests:
  1. reassign dispatches unassign then assign; the assign request echoes the
     unassign ACK version (not the pre-command version); optimistic overlay
     key `overlay-assign-<id>-<target>` renders.
  2. re-picking the currently assigned character is a no-op (zero network
     calls).
  3. assign-leg failure after a successful unassign keeps the honest
     unassigned state and surfaces the error (`costume-detail-error`,
     `Network problem` copy).
- **`integration_test/gherkin/steps/costume_assignment_steps.dart`** — new
  `I reassign costume {string} from {string} to {string}` step: taps the
  Reassign button keyed by the CURRENT character (`assign-costume-<id>
  -<currentChar>`) directly on the open detail screen, picks the target from
  the picker. Generalized the seed Given step to accept any costume symbol
  (`given3`), and made the optimistic step tolerate the reconcile race on a
  fast localhost backend (accept the optimistic overlay OR the already-
  reconciled authoritative key — the widget tier pins the strict overlay
  contract; a genuine command failure shows neither and still times out).
- **`integration_test/gherkin/steps/seed_http.dart`** — the seed now also
  creates a SECOND, distinct unassigned costume `c-r` mapped in
  `SeedCache`. The suite shares ONE seed run, so scenario 1's assign mutates
  `c-7`; the reassignment scenario operates on its own `c-r` that no other
  scenario touches.
- **`features-spec/costume_assignment.feature`** — new promoted scenario
  "Reassigning an assigned costume runs the unassign→assign sequence":
  performs the first assignment (`c-r` → ch-3), waits for the projection,
  then reassigns (`c-r` → ch-9) and asserts the optimistic overlay +
  projected reconciliation. No `@pending` tag — it enters the default
  on-device `not @pending` pass.
- **OpenSpec change artifact** at `openspec/changes/454-costume-reassign-sequence/`.

## Non-goals

- **No backend change** — no new/relaxed reassign command, no
  `backend/openapi.yaml` change, no `vendor/breakdown_api` regeneration, no
  Fluent/problem-registry edits. The atomic backend reassign semantic remains
  a possible follow-up proposal; this change is fully client-contained.
- **No change to the `@critical` / `@pending` discipline**
  (`tool/check_gherkin.sh` already accepts a fully promoted critical scope).
- **No change to the first-assignment path** or the viewer-denial path.

## Decisions

- **D1 (client-side sequence vs. backend reassign semantic):** the issue's
  AC-1 decision is made — a client-side **unassign→assign sequence** (chosen
  over a backend reassign command). Rationale: fully client-contained (no
  `backend/openapi.yaml` change, no `breakdown_api` regeneration, no Fluent /
  problem-code edits); the two-command sequence with fence-friendly version
  echoes satisfies the backend's existing aggregate rules (unassign requires
  an assignment; assign requires an unassigned costume). The sequence is
  intentionally NOT atomic: an assign-leg failure after a successful unassign
  leaves the costume genuinely unassigned, and that truth is surfaced
  honestly (overlay + `costumesCommandErrorProvider`). An atomic backend
  reassign semantic remains a possible follow-up proposal.
- **D2 (same-character no-op):** re-picking the already-assigned character is
  treated as a no-op success on the client (the backend 422s the
  same-character reassign command). No network call, no error.

## Acceptance criteria (from issue #454)

- [x] Decide: client-side unassign→assign sequence (with fence-friendly
      version echoes) — chosen over a backend reassign semantic.
- [x] Reassign flow green in a widget test (three new widget tests: happy
      sequence + version echo, same-character no-op, assign-leg failure
      honesty).
- [x] On-device reassignment scenario added to `costume_assignment.feature`
      and promoted (no `@pending`) — un-pends the affected on-device path
      that previously 409'd. Verified on device: `bash tool/run_gherkin.sh`
      → 4 scenarios / 26 steps passed; the reassignment scenario's costume
      ended at version 4 / ch-9 (create→assign ch-3→unassign→assign ch-9),
      proving the unassign→assign sequence ran on device.

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | code change + version bump `0.3.0-alpha.11+20` → `0.3.0-alpha.12+21` | Controller reassign sequence + tests + Gherkin step/feature |
| `breakdown_api` (`vendor/breakdown_api/`) | none | `backend/openapi.yaml` unchanged |
| `*.g.dart` / `*.freezed.dart` | none | No `@freezed` / `@riverpod` / drift edits |
