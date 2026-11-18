<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Tasks — Costume Reassign client-side unassign→assign sequence (issue #454)

## Done

- **Client-side reassign sequence in `CostumesController.assign`**
  (`lib/features/costumes/costumes_controller.dart`): no-op for the same
  character; unassign→assign sequence for a different character (assign
  echoes the unassign ACK version); single bounded reconcile after the final
  ack; honest failure surface on an assign-leg failure; `// AUTHZ-GATE:`
  retained. First-assignment path unchanged.
- **Widget tests** (`test/features/costumes/costume_detail_screen_test.dart`):
  reassign happy path (unassign then assign, assign echoes unassign ACK,
  `overlay-assign-*` key), same-character no-op (zero calls), assign-leg
  failure keeps honest unassigned state + error copy.
- **On-device Gherkin coverage**
  (`integration_test/gherkin/steps/costume_assignment_steps.dart` +
  `integration_test/gherkin/steps/seed_http.dart` +
  `features-spec/costume_assignment.feature`):
  - New promoted reassignment scenario (first-assign `c-r`→ch-3, wait
    projection, reassign `c-r`→ch-9; assigns its own seed costume `c-r` so
    scenario 1's mutation of `c-7` cannot leak into it).
  - New `I reassign costume ... from ... to ...` step tapping the detail's
    Reassign button in place.
  - Generalized the seed Given step to accept any costume symbol
    (`given3`), and made the optimistic step tolerate the reconcile race
    (accept optimistic OR already-reconciled key).

## Verified

- `dart format --set-exit-if-changed .`: clean
- `flutter analyze`: clean
- `flutter test`: 975 passed
- `bash tool/check_gherkin.sh`: passed
- **On-device `bash tool/run_gherkin.sh`:** 4 scenarios / 26 steps passed
  (smoke + first-assignment + reassignment + viewer-denial). The
  reassignment scenario's costume ended at version 4 / ch-9
  (create→assign ch-3→unassign→assign ch-9), proving the unassign→assign
  sequence ran on device.
- HTTP-level proof: a plain assign on an assigned costume 409s
  `costume.already-assigned`; unassign(echo v)→assign(echo ack) lands 200/200.
