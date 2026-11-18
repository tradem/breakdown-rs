<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Tasks: 670-easter-egg-redesign-karl-kleiderbuegel

## 1. Rename

- [x] 1.1 Rename `EasterEggId.karlKlammer` → `karlKleiderbuegel` with prefs
      key `easter_eggs.karl_kleiderbuegel` + one-time value migration from
      `easter_eggs.karl_klammer` (old key removed; explicit new-key value
      wins; failed removal non-fatal).
- [x] 1.2 Rename classes/files/test keys: `KarlKlammerFigure` →
      `KarlKleiderbuegelFigure`, `KarlKlammerOverlay` →
      `KarlKleiderbuegelOverlay`, `karl_klammer_*.dart` →
      `karl_kleiderbuegel_*.dart`, `karl-klammer-*` keys →
      `karl-kleiderbuegel-*`.
- [x] 1.3 Rename l10n keys + strings (de/en): "Karl Klammer" →
      "Karl Kleiderbügel"; `flutter gen-l10n`.
- [x] 1.4 Update design docs (`docs/design/screens/settings.md`,
      `docs/design/glossary.md`): names, copy keys, egg row icon →
      `checkroom`.

## 2. Déjà-vu cat redesign

- [x] 2.1 Port the approved Ghibli-inspired cat SVG to `_CatPainter`
      (radial fur gradient, rim-light gradient, tail, ears, camera-facing
      eyes, whiskers, paws) in the approved fixed palette (D3).
- [x] 2.2 Keep the motion contracts: travel/glance math, static phase,
      remove-animations behavior; express the glance as head tilt +
      pupil shift; add a pause-damped walk bob.

## 3. Karl Kleiderbügel redesign

- [x] 3.1 Port the approved hanger SVG to the painter (dark contour +
      4-stop metal core strokes, wire twist, inner strut, glint lines,
      −3° group rotation) in the approved fixed palette (D3).
- [x] 3.2 Rebuild the SVG's `feDropShadow` Flutter-natively
      (`MaskFilter.blur`, σ=3, dy=3, 20% `#4a5568`) beneath eyes and
      mouth (D2).
- [x] 3.3 Adapt the five-pose expression table + blink onto the new face
      geometry; keep the motion periods/phase-continuity contracts (D4).

## 4. Tests & guardrails

- [x] 4.1 Update token-discipline test: literals confined to the
      documented `_Art` palette block (D3).
- [x] 4.2 Prefs-key migration tests (carry-over, explicit-choice-wins,
      old-key cleanup, no-old-key no-op).
- [x] 4.3 Regenerate all affected goldens (figure, host screens, cat
      walker) in light + dark; repaint/phase proofs stay green.
- [x] 4.4 Dev-time fidelity check: painter output pixel-compared against
      `rsvg-convert` renders of both approved SVGs.
- [x] 4.5 `dart format`, `flutter analyze`, `flutter test` (1669 passing),
      `flutter gen-l10n` drift-free; `grep -ri klammer` has no
      user-facing hits.
