<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Proposal: Karl Klammer figure redesign — comic-vector hanger with a face (issue #614)

## Why

The Karl Klammer Easter egg (issue #516) shipped a `CustomPainter` figure
that is geometrically a plain clothes-hanger glyph: the two eyes exist but
are 1.1 px dots on the hook stem (invisible at the 72 px logical box), the
body is a thin stroke outline, and only the `running` pose animates (a
single sine wobble). It does not read as a *character* and is not
recognisable as a hanger with eyes.

The PO decided (decision handshake, issue #614) on a **comic/vector**
redesign: an original, AGPL-3.0 own-work hanger character — recognisable as
a clothes hanger with clearly visible eyes, reminiscent of the classic
eager-assistant archetype without copying Microsoft's artwork — with an
expressive face, per-pose motion, blinking, idle life, and an extended
trigger set. The figure stays code-drawn (`CustomPainter`, no binary
assets) and colors stay design-token-only.

## What Changes

- **Filled comic-vector silhouette:** the stroke-only hanger becomes a
  filled body (hook, head, shoulders, bottom bar, and the previously
  promised-but-undrawn lower triangle) so the figure reads at small sizes.
- **Expressive head:** large eyes with visible sclera + pupils, eyebrows,
  and pose-specific mouths (grin / consolation frown / determined /
  thoughtful) — all from Material 3 color-scheme roles.
- **Animation scope:** periodic blink, gentle idle bob/sway, and a distinct
  motion signature per pose (`excited` swing, `droop` sag, `proud` bounce,
  `thinking` sway). Deterministic (single injected controller phase, no
  wall clock / randomness); the system "remove animations" setting still
  renders the static posed figure with all expressions visible.
- **Trigger extension (Tier-1):** a new `queued` flow state → a `thinking`
  pose ("let me think about it") for jobs that are queued but not yet
  running; the idle joke set grows from 3 to 5 entries with deterministic
  pose cycling. `clippyTipFor` stays pure and Flutter-import-free.
- **Design documentation:** the change's `design.md` carries the
  comic-vector proportions sketch (PlantUML Salt) and the
  eye/mouth/eyebrow state table per pose.
- **Copy:** new `aiImport.clippy.*` keys for the `queued` tip and the two
  extra idle jokes (de/en), plus glossary entries.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `flutter-easter-eggs`: the "Karl Klammer Assistant in the AI Import View"
  requirement is refined — the figure SHALL be a filled comic-vector hanger
  with a clearly visible expressive face, SHALL blink and idle-animate
  deterministically, SHALL render a distinct motion signature per pose, and
  SHALL expose the extended `queued`/`thinking` reaction and larger
  deterministic idle set. The accessibility contract (remove-animations
  static pose, non-modal, dismissible, screen-reader semantics, no network /
  no tracking) is unchanged.

> **Archive ordering:** this change MODIFIES a requirement that is first
> ADDED by the still-unarchived change `add-karl-klammer-easter-egg`
> (issue #516). Archive #516 before archiving this change so the base
> `flutter-easter-eggs` spec exists in `openspec/specs/`.

## Impact

- `frontend-flutter/lib/features/ai_import/clippy/karl_klammer_figure.dart`
  — `_HangerPainter` reworked (filled silhouette + expressive head +
  animations).
- `frontend-flutter/lib/features/ai_import/clippy/clippy_trigger.dart` —
  new `ClippyFlowState.queued`, `ClippyPose.thinking`, expanded idle set.
- `frontend-flutter/lib/features/ai_import/import_jobs/` — job screens map
  `JobStatus.pending` to `queued` (was folded into `running`).
- `frontend-flutter/lib/l10n/app_{de,en}.arb` — new `aiImport.clippy.*`
  keys; `flutter gen-l10n`.
- `docs/design/glossary.md` — new copy-key rows.
- Tests + goldens: repaint/blink determinism, per-pose rendering, trigger
  mapping, token compliance; goldens regenerated.
- **No backend/API change** — `backend/openapi.yaml` untouched, no Dart
  client regeneration.
