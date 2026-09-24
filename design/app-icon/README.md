<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Breakdown-RS App Icon

Launcher icon of the Breakdown-RS clients (Android first). This directory
is the **source of truth** for the icon's construction; the Android raster
and vector layer artifacts are derived from it and regenerated/verified by
`frontend-flutter/scripts/gen-app-icon.sh`.

## Motif

- **Kleiderbügel (clothes hanger)** — the official Material Symbols
  `checkroom` glyph, the same mark the app uses for the costuming tab
  (`Icons.checkroom`). Costume = the product; the exact in-app glyph
  guarantees brand coherence between home screen and app UI, and the
  official glyph provides a correct, recognizable hook.
- **Zahnrad (gear) below the hanger** — the official Material Symbols
  `settings` glyph scaled down, as a nod to the Rust backend / engineering
  core of the monorepo. Deliberately *below* the hanger: a base the
  wardrobe "runs on", not a competing hero motif.
- **Hintergrund** — flat brand seed teal
  (`design/tokens/color.json` → `color.brand.seed`, `#009688`), Material You
  style: flat, reduced, no gradients or skeuomorphism.

The term "Breakdown" is deliberately **not** rendered literally (no broken
parts, no warning aesthetics) — the scheduling sense (Szenen-Aufbruch,
Disposition) lives in the neutral wardrobe-on-machinery composition.

## Files

| File | Role |
|---|---|
| `app_icon.svg` | Full-bleed 108dp composition (background + glyph). Render source for legacy launcher PNGs. |
| `foreground.svg` | Glyph-only 108dp layer (transparent). Source of truth for the adaptive foreground **and** monochrome layer. |
| `frontend-flutter/android/.../res/mipmap-anydpi-v26/ic_launcher.xml` | Adaptive-icon layer wiring (background color / foreground / monochrome). |
| `frontend-flutter/android/.../res/drawable/ic_launcher_foreground.xml` | VectorDrawable mirroring `foreground.svg` 1:1 (path data byte-identical AND glyph transforms normalized-equivalent, verified). |
| `frontend-flutter/android/.../res/values/colors.xml` | `ic_launcher_background` = brand seed teal. |
| `frontend-flutter/android/.../res/mipmap-{mdpi..xxxhdpi}/ic_launcher.png` | Legacy raster (pre-API-26 launchers; 48dp reference × density). Regenerated, never hand-edit. |

## Construction rules (verified, not approximated)

1. **Adaptive-icon spec:** all layers are 108dp; OEM masks crop to roughly
   the inner 66dp circle. The glyph's max radius from center is
   **31.02dp** (pixel-analytically verified by `gen-app-icon.sh` on every
   regeneration; limit 33dp) — nothing is clipped by circle or squircle
   masks.
2. **Layout constants:** checkroom centered at (54, 42), scale 0.06
   (48dp wide); gear centered at (54, 74.5), scale 0.025 (21dp diameter);
   ≥3.5dp clear gap between hanger bar and gear (Material negative-space
   rule: gaps must not collapse at small sizes). The SVGs express these as
   `translate(x y) scale(s) translate(px py)` chains; the VectorDrawable
   bakes the composed `translateX/translateY/scaleX/scaleY`. `gen-app-icon.sh`
   verifies the two forms evaluate to the same affine matrix, so a
   transform-only edit to both SVGs that leaves the VectorDrawable stale
   fails the drift check.
3. **Monochrome layer (Android 13+ themed icons):** the glyph is a
   single-color (white) silhouette — the same VectorDrawable is reused for
   the `<monochrome>` layer and tinted by the system's theme palette.
4. **No hand-sketched paths:** both glyphs are the official Material
   Symbols path data (see License).

## Regeneration / drift check

```bash
bash frontend-flutter/scripts/gen-app-icon.sh          # regenerate + verify
bash frontend-flutter/scripts/gen-app-icon.sh --check   # committed-tree drift check
```

CI enforces the committed-tree drift check on PRs and main
(`.github/workflows/icon-drift.yml`): any change under `design/app-icon/**`, the
Android icon resources (`frontend-flutter/android/app/src/main/res/**`), or the
script itself that leaves a stale source↔raster↔VectorDrawable combination fails
this gate with the script's `DRIFT DETECTED` / `ERROR` output.

The script verifies that the glyph path data in `app_icon.svg`,
`foreground.svg`, and `ic_launcher_foreground.xml` stays byte-identical,
that the two SVGs carry byte-identical transform attributes, and that the
SVG transform chains normalize to the same affine matrix as the
VectorDrawable's baked translate/scale groups (hand-maintained
VectorDrawables drift silently otherwise, and a transform-only edit to both
SVGs would leave the adaptive layer stale while the legacy rasters move).
It also asserts deterministic rasterizer output and re-runs the safe-zone
check.

## License / attribution

- The icon composition and this pipeline: **AGPL-3.0**
  (see repository root).
- Embedded glyph path data: **Material Symbols** (`checkroom`,
  `settings`), Copyright Google LLC, licensed under
  **Apache-2.0** — reuse and modification of the path data is permitted
  under Apache-2.0; the composed icon as a whole stays AGPL-3.0.
