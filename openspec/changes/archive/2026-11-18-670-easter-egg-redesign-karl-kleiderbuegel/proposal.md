<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Ghibli-inspired Déjàvu cat + Karl Klammer → Karl Kleiderbügel redesign (issue #670)

## Why

The 2026-10-14/15 design walkthrough approved two visual redesigns of the
Easter eggs (session outcome, artwork embedded in the issue):

1. **Déjàvu cat** — a Ghibli-inspired black cat (seated pose, big head,
   large alert eyes, tail wrapped around the front paws; near-black radial
   fur gradient + soft blue-grey rim light, readable on light AND dark)
   replaces the minimal side-view silhouette in `_CatPainter`.
2. **"Karl Klammer" → "Karl Kleiderbügel"** — the assistant is renamed
   app-wide and redesigned as the approved user-drawn clothes-hanger
   artwork (rounded triangle with perspective, wire twist at the neck,
   inner strut, sweeping hook, expressive face, 4-stop metal gradient +
   glint lines).

Both SVGs are the approved design direction; this change ports them into
the app.

## Decisions

- **D1 — Rendering: hand-ported `CustomPainter`s, not flutter_svg.**
  Both figures are animated (`CustomPainter`s drive per-pose motion,
  blink, walk/glance). Every SVG construct maps 1:1 to Flutter painting
  (radial/linear gradients, bézier paths, round caps/joins, group
  rotation) except `feDropShadow`, which is rebuilt Flutter-natively
  (D2). Fidelity is verified dev-time by pixel-comparing the painter's
  golden output against an `rsvg-convert` reference render of the
  approved SVG. Fallback if a figure shows visible drift: ship that
  figure's SVG via flutter_svg (already a dependency).
- **D2 — feDropShadow: rebuilt, not dropped.** The Karl face group's
  subtle shadow is redrawn as a blurred underlay (`MaskFilter.blur`,
  σ=3, dy=3, 20% `#4a5568`) beneath the eyes/mouth — visually near
  identical to the SVG filter. Decision documented here per the issue's
  acceptance criterion.
- **D3 — Approved-artwork palette exception.** The approved SVG palettes
  are fixed hex constants (near-black fur, blue-grey rim, white-metal
  hanger) chosen by design to read on both themes — the same exception
  as the launcher icon. Constants carry a comment pointing at the
  approved artwork; goldens in both themes protect the readability.
- **D4 — Motion contracts untouched.** Walk/travel math, the déjà-vu
  glance beat, the static phase (`remove animations`), Karl's five
  poses, blink window and per-pose periods are all preserved; only the
  drawn geometry is restyled. The cat's glance beat is expressed as a
  head tilt toward the camera (the approved art already looks at the
  viewer) instead of the old side-glance eye shift.
- **D5 — Prefs-key rename + one-time migration.** The persisted key
  `easter_eggs.karl_klammer` is renamed to
  `easter_eggs.karl_kleiderbuegel`; on the first read after the update,
  a value under the old key is carried over to the new key and the old
  key removed (same pattern as the #615 legacy migration). No user
  loses their toggle state.
- **D6 — Historical references stay.** Comments referencing the archived
  OpenSpec change id `add-karl-klammer-easter-egg` and the issue titles
  keep the old name (renaming history would falsify the record). The
  acceptance criterion requires no *user-facing* hits.

## Scope

- Restyle `dejavu_cat.dart`'s painter to the approved cat artwork; keep
  `DejaVuCatOverlay` / `DejaVuCatWalker` public API and gates (#615/#640
  surfaces: splash, seasons empty state, settings preview).
- Rename + redesign the Karl figure/overlay (`karl_kleiderbuegel_*`),
  l10n strings (de/en), code identifiers, test keys, prefs key (D5).
- Update/extend tests: renamed identifiers, new goldens (light + dark
  for both figures), prefs-key migration test, walk-phase repaint proof.

## Non-goals

- No behavioral changes to when/how the eggs trigger (re-verified only).
- No backend changes.
- No renaming of archived OpenSpec change ids or issue titles.

## Acceptance criteria (mirrors issue #670)

- [ ] New cat rendering matches the approved SVG (golden tests, light + dark)
- [ ] Karl Kleiderbügel rendered from a faithful painter port;
      drop-shadow decision documented (D2)
- [ ] App-wide rename — `grep -ri "klammer"` returns no user-facing hits
- [ ] Easter-egg trigger contract re-verified: cat visible per #640 on
      regular screens in both themes (existing surface tests stay green)
- [ ] Existing easter-egg widget tests updated and green
