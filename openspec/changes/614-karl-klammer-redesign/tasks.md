<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Tasks: Karl Klammer figure redesign (issue #614)

## 1. Design & copy artifacts

- [x] 1.1 `design.md` — comic-vector proportions sketch (Salt) + the
      per-pose expression table (done in this change).
- [x] 1.2 `docs/design/glossary.md` — add the `queued` tip and the two
      new idle-joke rows (`aiImport.clippy.queued`, `idle4`, `idle5`).
- [x] 1.3 `lib/l10n/app_de.arb` + `app_en.arb` — add the three new keys;
      run `flutter gen-l10n`; de/en parity clean.
- [x] 1.4 `openspec validate 614-karl-klammer-redesign --strict` +
      `scripts/check-design-diagrams.sh`.

## 2. Trigger logic (Tier-1, pure)

- [x] 2.1 `clippy_trigger.dart`: add `ClippyFlowState.queued`,
      `ClippyPose.thinking`, `ClippyTipKey.queued`, and `idle4`/`idle5`;
      expand the deterministic idle cycle to five entries with pose
      cycling.
- [x] 2.2 `clippy_test.dart`: assert the `queued` mapping, the five-step
      idle cycle + pose sequence, and mapping totality.

## 3. Figure redesign (CustomPainter)

- [x] 3.1 Rework `_HangerPainter`: filled comic-vector silhouette (hook,
      head, shoulders, bottom bar, lower triangle) with `primary` fill +
      `outline` edge; expressive head (sclera + pupils, eyebrows,
      per-pose mouth); generalize the scale transform.
- [x] 3.2 Animation: single injected controller phase driving
      per-pose motion + `karlEyesClosed(phase)` blink; `animate: false`
      renders the static pose with no controller.
- [x] 3.3 Token discipline: colors only from the M3 color-scheme roles.

## 4. Job-screen trigger wiring

- [x] 4.1 `job_status_screen.dart` + `jobs_screen.dart`: map
      `JobStatus.pending` → `ClippyFlowState.queued` (was folded into
      `running`).

## 5. Tests & goldens

- [x] 5.1 Widget: repaint proof (phase goldens differ), blink determinism
      (`karlEyesClosed` + phase goldens), per-pose rendering, token
      compliance (no raw color literals in the figure source).
- [x] 5.2 Regenerate + inspect the goldens (`--update-goldens`); confirm
      the figure reads as a hanger with a visible face.
- [x] 5.3 Keep the remove-animations / non-modal / semantics tests green.

## 6. Validation & CI gates

- [x] 6.1 `dart format --set-exit-if-changed .`; `flutter analyze`;
      `breakdown_lints` runner clean.
- [x] 6.2 `flutter test --coverage`; Err-branch assertions unchanged.
- [x] 6.3 No `backend/openapi.yaml` change → no client regen; no
      `*.g.dart`/`*.freezed.dart` hand-edits.
