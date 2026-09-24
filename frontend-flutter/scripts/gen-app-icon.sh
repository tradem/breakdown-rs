#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)

# Regenerate the Breakdown-RS launcher icon raster assets from the icon
# sources under `design/app-icon/` (repo root) and verify layer consistency.
#
# This script is the SINGLE source of truth for raster regeneration (the
# pattern mirrors scripts/regen-client.sh):
#   - Sources (hand-maintained, the "API spec" of this pipeline):
#       design/app-icon/app_icon.svg   full-bleed icon (background + glyph)
#       design/app-icon/foreground.svg  glyph-only layer (transparent)
#   - Outputs (regenerated — never hand-edit):
#       android/.../mipmap-{mdpi..xxxhdpi}/ic_launcher.png   legacy raster
#   - Hand-maintained Android resources verified (NOT regenerated) for
#     consistency against foreground.svg:
#       android/.../drawable/ic_launcher_foreground.xml       vector glyph
#       android/.../mipmap-anydpi-v26/ic_launcher.xml         layer wiring
#       android/.../values/colors.xml                          bg color
#     (VectorDrawable cannot be rasterized from SVG by rsvg-convert, so it
#     is hand-authored in lockstep; this script FAILS the run if the glyph
#     path data drifts between the SVG sources and the VectorDrawable.)
#
# Usage:
#   bash scripts/gen-app-icon.sh            regenerate + verify (default)
#   bash scripts/gen-app-icon.sh --check    verify-only against committed
#                                          tree (byte-identical drift check,
#                                          exit 1 on drift)
#
# Requirements: rsvg-convert (librsvg). The safe-zone verification is
# best-effort and additionally uses python3 + Pillow when available.

set -euo pipefail

# Resolve the frontend-flutter root from this script's location, and the
# monorepo root from that — works from any caller working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FRONTEND_DIR/.." && pwd)"

ICON_DIR="$REPO_ROOT/design/app-icon"
RES_DIR="$FRONTEND_DIR/android/app/src/main/res"

FULL_ICON_SVG="$ICON_DIR/app_icon.svg"
FOREGROUND_SVG="$ICON_DIR/foreground.svg"
VECTOR_DRAWABLE="$RES_DIR/drawable/ic_launcher_foreground.xml"

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

die() { echo "ERROR: $*" >&2; exit 1; }

command -v rsvg-convert >/dev/null 2>&1 \
  || die "rsvg-convert not found (install librsvg-tools / librsvg)"

for f in "$FULL_ICON_SVG" "$FOREGROUND_SVG" "$VECTOR_DRAWABLE" \
         "$RES_DIR/mipmap-anydpi-v26/ic_launcher.xml" \
         "$RES_DIR/values/colors.xml"; do
  [[ -f "$f" ]] || die "missing icon source/resource: $f"
done

# ---------------------------------------------------------------------------
# 1. Consistency check: glyph path data must be byte-identical across
#    app_icon.svg, foreground.svg, and the VectorDrawable.
# ---------------------------------------------------------------------------
extract_svg_paths() {
  # All d="..." attributes (one per glyph), sorted for order-insensitive
  # comparison of the two SVGs.
  grep -o 'd="[^"]*"' "$1" | sort
}

extract_vector_paths() {
  # All android:pathData="..." attributes.
  grep -o 'android:pathData="[^"]*"' "$1" | sed 's/^android:pathData=/d=/' | sort
}

extract_svg_transforms() {
  grep -o 'transform="[^"]*"' "$1" | sort
}

extract_vector_transforms() {
  grep -oE 'android:(translateX|translateY|scaleX|scaleY)="[^"]*"' "$1" | sort
}

diff <(extract_svg_paths "$FULL_ICON_SVG") <(extract_svg_paths "$FOREGROUND_SVG") >/dev/null \
  || die "app_icon.svg and foreground.svg glyph path data differ"

diff <(extract_svg_paths "$FOREGROUND_SVG") <(extract_vector_paths "$VECTOR_DRAWABLE") >/dev/null \
  || die "foreground.svg and ic_launcher_foreground.xml glyph path data differ"

# Background color: colors.xml must carry the brand seed teal.
grep -q 'ic_launcher_background">#009688<' "$RES_DIR/values/colors.xml" \
  || die "values/colors.xml: ic_launcher_background is not #009688 (brand seed)"

# ---------------------------------------------------------------------------
# 2. Safe-zone verification (best-effort): the glyph must stay inside the
#    33dp-radius centered circle of the 108dp canvas (adaptive-icon spec).
#    Recorded baseline for the current glyph: 31.24dp.
# ---------------------------------------------------------------------------
verify_safe_zone() {
  local render="$1" label="$2"
  if ! python3 -c "import PIL" >/dev/null 2>&1; then
    echo "WARN: safe-zone check skipped (python3 + Pillow not available): $label"
    return 0
  fi
  python3 - "$render" <<'PYEOF' || die "safe-zone violation in $label (see above)"
import math, sys
from PIL import Image
img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
center = (w / 2.0, h / 2.0)
max_r = 0.0
for y in range(h):
    for x in range(w):
        if min(img.getpixel((x, y))) > 240:
            r = math.hypot(x - center[0], y - center[1]) * 108.0 / w
            max_r = max(max_r, r)
if max_r >= 33.0:
    print(f"FAIL: glyph radius {max_r:.2f}dp >= 33dp safe zone")
    sys.exit(1)
print(f"safe zone OK ({max_r:.2f}dp < 33dp)")
PYEOF
}

# ---------------------------------------------------------------------------
# 3. Raster regeneration: legacy ic_launcher.png in all mipmap densities
#    (pre-API-26 launchers and Play artifacts; API 26+ uses the adaptive XML).
#    48dp reference size, scaled by density factor.
# ---------------------------------------------------------------------------
densities=(mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192)

if [[ $CHECK_ONLY -eq 1 ]]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  for entry in "${densities[@]}"; do
    density="${entry%%:*}"
    size="${entry##*:}"
    rsvg-convert -w "$size" -h "$size" -o "$tmpdir/$density.png" "$FULL_ICON_SVG"
    committed="$RES_DIR/mipmap-$density/ic_launcher.png"
    if ! cmp -s "$tmpdir/$density.png" "$committed"; then
      echo "DRIFT DETECTED in mipmap-$density/ic_launcher.png — regenerate with:" >&2
      echo "  bash scripts/gen-app-icon.sh" >&2
      exit 1
    fi
  done
  verify_safe_zone "$tmpdir/mdpi.png" "legacy raster (check mode)"
  echo "OK: committed icon rasters match the design sources (no drift)."
  exit 0
fi

for entry in "${densities[@]}"; do
  density="${entry%%:*}"
  size="${entry##*:}"
  mkdir -p "$RES_DIR/mipmap-$density"
  rsvg-convert -w "$size" -h "$size" -o "$RES_DIR/mipmap-$density/ic_launcher.png" "$FULL_ICON_SVG"
  echo "rendered mipmap-$density/ic_launcher.png (${size}x${size})"
done

# ---------------------------------------------------------------------------
# 4. Post-regeneration verification: deterministic output (a second pass
#    into a throwaway must be byte-identical — drift-guard against
#    nondeterministic rasterizers) and safe-zone compliance.
# ---------------------------------------------------------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
for entry in "${densities[@]}"; do
  density="${entry%%:*}"
  size="${entry##*:}"
  rsvg-convert -w "$size" -h "$size" -o "$tmpdir/$density.png" "$FULL_ICON_SVG"
  cmp -s "$tmpdir/$density.png" "$RES_DIR/mipmap-$density/ic_launcher.png" \
    || die "rasterization is not deterministic for $density — do not commit"
done

verify_safe_zone "$RES_DIR/mipmap-xxxhdpi/ic_launcher.png" "regenerated raster"

echo "OK: launcher icon rasters regenerated and verified."
