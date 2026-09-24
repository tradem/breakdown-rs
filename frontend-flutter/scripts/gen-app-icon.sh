#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)
# Co-authored-by: deepseek-v4-flash (neuralwatt)

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
#     path data OR its transform (position/scale) drifts between the SVG
#     sources and the VectorDrawable — a transform-only edit to both SVGs
#     would otherwise change the legacy rasters while the adaptive
#     VectorDrawable stays stale, silently diverging pre-API-26 and
#     API-26+ launchers.)
#
# Usage:
#   bash scripts/gen-app-icon.sh            regenerate + verify (default)
#   bash scripts/gen-app-icon.sh --check    verify-only against committed
#                                          tree (byte-identical drift check,
#                                          exit 1 on drift)
#
# Requirements: rsvg-convert (librsvg). Glyph transform-consistency and the
# safe-zone pixel analysis additionally use python3 (transform check uses the
# stdlib XML parser and is mandatory — failure to run it is a hard error,
# not a skip; the safe-zone check is best-effort and additionally needs
# Pillow, degrading to a warning when absent).
#
# BYTE-STABILITY NOTE: rsvg-convert's PNG *byte* output is not stable across
# librsvg versions (pixels are, the PNG encoding is not). The committed
# rasters and the --check drift gate are therefore coupled to one librsvg
# version: the canonical one installed by .github/workflows/icon-drift.yml
# (ubuntu-24.04's apt librsvg 2.58.0). Regenerate with that version — a
# locally regenerated tree produced by a different librsvg will correctly
# report byte drift against the committed rasters. Verify level with the
# same release used by CI (see design/app-icon/README.md).

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
ADAPTIVE_ICON="$RES_DIR/mipmap-anydpi-v26/ic_launcher.xml"

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
         "$ADAPTIVE_ICON" \
         "$RES_DIR/values/colors.xml"; do
  [[ -f "$f" ]] || die "missing icon source/resource: $f"
done

# Adaptive-icon layer wiring: assert the expected background/foreground/
# monochrome references. Existence alone is not enough — dropping the
# monochrome layer (disabling Android 13+ themed icons) or pointing the
# foreground at the wrong drawable must fail both --check and regeneration.
assert_adaptive_layer() {
  local element="$1" drawable="$2"
  grep -Eq "^[[:space:]]*<${element}[[:space:]]+android:drawable=\"${drawable}\"[[:space:]]*/>[[:space:]]*$" "$ADAPTIVE_ICON" \
    || die "adaptive icon layer wiring mismatch: ${element} -> ${drawable}"
}
assert_adaptive_layer background "@color/ic_launcher_background"
assert_adaptive_layer foreground "@drawable/ic_launcher_foreground"
assert_adaptive_layer monochrome "@drawable/ic_launcher_foreground"

# ---------------------------------------------------------------------------
# 1. Consistency check. Path data must be byte-identical across app_icon.svg,
#    foreground.svg, and the VectorDrawable. Glyph transforms must match too,
#    with the path->transform ASSOCIATION preserved (never a sorted-list
#    compare): every glyph's full transform chain (ancestor <g> + own) must be
#    byte-identical between the two SVGs AND normalize to the same affine
#    matrix as the VectorDrawable's baked translate/scale groups. Without
#    these checks, a transform-only edit to both SVGs — a swap, a parent <g>
#    shift, a nested group — passes every path-data assertion while the legacy
#    rasters move and the adaptive VectorDrawable stays stale.
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

diff <(extract_svg_paths "$FULL_ICON_SVG") <(extract_svg_paths "$FOREGROUND_SVG") >/dev/null \
  || die "app_icon.svg and foreground.svg glyph path data differ"

diff <(extract_svg_paths "$FOREGROUND_SVG") <(extract_vector_paths "$VECTOR_DRAWABLE") >/dev/null \
  || die "foreground.svg and ic_launcher_foreground.xml glyph path data differ"

# ---------------------------------------------------------------------------
# 1b. Normalized transform equivalence (SVG ↔ VectorDrawable). The SVG chains
#     translate(x y) scale(s) translate(px py); the VectorDrawable bakes the
#     composed translateX/translateY/scaleX/scaleY. Different syntax, same
#     layout — so the affine matrices the two forms evaluate to are compared
#     per glyph (association keyed by identical path data). Walks the tree
#     root→leaf so ancestor <g> transforms and nested groups are composed in.
#     Requires python3 (stdlib only). Fail-closed: without it the transform
#     guarantee cannot be upheld, so this dies instead of degrading to a
#     warning. Unsupported or unparsed SVG ops (rotate/skew/…) raise an ERROR
#     — a transform not representable as a translate/scale group forces an
#     explicit bake into the drawable.
# ---------------------------------------------------------------------------
verify_transform_consistency() {
  command -v python3 >/dev/null 2>&1 \
    || die "python3 not found (required for the glyph transform-consistency check)"
  python3 - "$FULL_ICON_SVG" "$FOREGROUND_SVG" "$VECTOR_DRAWABLE" <<'PYEOF' || die "icon SVG/VectorDrawable glyph transform drift (see above)"
import re
import sys
import xml.etree.ElementTree as ET

TOL = 1e-6
IDENT = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def mul(m, n):
    """Compose affine matrices (column vectors): (m * n) x, i.e. m applied
    after n. Each matrix is (a, b, c, d, e, f) with [a c e; b d f; 0 0 1]."""
    a, c, e = m[0], m[2], m[4]
    b, d, f = m[1], m[3], m[5]
    A, C, E = n[0], n[2], n[4]
    B, D, F = n[1], n[3], n[5]
    return (
        a * A + c * B,
        b * A + d * B,
        a * C + c * D,
        b * C + d * D,
        a * E + c * F + e,
        b * E + d * F + f,
    )


def svg_matrix(transform_str):
    """Canonical affine matrix (a, b, c, d, e, f) of an SVG transform list.

    Column-vector convention: x' = M x with M = [a c e; b d f; 0 0 1]. The
    transform list is post-multiplied in list order (SVG 1.1), so
    `translate(54 42) scale(0.06) translate(-480 479)` yields
    M = T(54,42) * S(0.06) * T(-480,479) -- the leftmost op is composed last
    (applied first to the glyph in viewport space). Empty/missing transform
    is the identity. Fail-closed: mixed-case op names (skewX/skewY) and any
    text left unconsumed by the parser raise instead of being dropped.
    """
    a, b, c, d, e, f = IDENT
    if not transform_str.strip():
        return (a, b, c, d, e, f)
    func_re = r"[A-Za-z]+\s*\([^)]*\)"
    funcs = re.findall(r"([A-Za-z]+)\s*\(([^)]*)\)", transform_str)
    leftover = re.sub(func_re, "", transform_str).replace(",", "").strip()
    if leftover:
        raise ValueError(f"unparsed transform text {leftover!r} in: {transform_str!r}")
    for name, args in funcs:
        ws = [float(x) for x in args.replace(",", " ").split()]
        if name == "translate":
            tx = ws[0]
            ty = ws[1] if len(ws) > 1 else 0.0
            e, f = a * tx + c * ty + e, b * tx + d * ty + f
        elif name == "scale":
            sx, sy = ws[0], ws[1] if len(ws) > 1 else ws[0]
            a, b, c, d = a * sx, b * sx, c * sy, d * sy
        elif name == "matrix":
            na = a * ws[0] + c * ws[1]
            nb = b * ws[0] + d * ws[1]
            nc = a * ws[2] + c * ws[3]
            nd = b * ws[2] + d * ws[3]
            ne = a * ws[4] + c * ws[5] + e
            nf = b * ws[4] + d * ws[5] + f
            a, b, c, d, e, f = na, nb, nc, nd, ne, nf
        else:
            raise ValueError(
                f"transform op {name!r} is not representable in a VectorDrawable "
                "translate/scale group; bake it into the drawable and mirror it "
                f"here: {transform_str!r}"
            )
    return (a, b, c, d, e, f)


def vd_matrix(at):
    """VectorDrawable group attrs (namespace-stripped) -> canonical matrix.

    Android resolves a group as
      M = T(translateX + pivotX, translateY + pivotY) * S(scaleX, scaleY)
          * T(-pivotX, -pivotY)
    (pivot defaults to 0), reducing with pivot 0 to
    [scaleX 0 translateX; 0 scaleY translateY].
    """
    tx = float(at.get("translateX", "0"))
    ty = float(at.get("translateY", "0"))
    sx = float(at.get("scaleX", "1"))
    sy = float(at.get("scaleY", "1"))
    px = float(at.get("pivotX", "0"))
    py = float(at.get("pivotY", "0"))
    return (sx, 0.0, 0.0, sy, tx + px - sx * px, ty + py - sy * py)


def _local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else tag


def _attrs(el):
    return {_local(k): v for k, v in el.attrib.items()}


def parse_svg(path):
    """Glyph path-data (key) -> (transform chain string, composed matrix).

    Walks the tree root→leaf: every ancestor <g> transform is composed into
    the matrix and appended to the chain, so parent-transform edits and
    nested groups are reflected, and the chain preserves the association
    between each path and all of its transforms.
    """
    out = {}

    def walk(el, m, chain):
        tr = _attrs(el).get("transform", "")
        if tr:
            m = mul(m, svg_matrix(tr))
            chain = f"{chain} {tr}".strip()
        if _local(el.tag) == "path":
            d = _attrs(el).get("d")
            if d is not None:
                out[d] = (chain, m)
        for ch in el:
            walk(ch, m, chain)

    walk(ET.parse(path).getroot(), IDENT, "")
    return out


def parse_vd(path):
    """Glyph path-data (key) -> (innermost group attrs, composed matrix)."""
    out = {}

    def walk(el, m, attrs):
        if _local(el.tag) == "group":
            attrs = _attrs(el)
            m = mul(m, vd_matrix(attrs))
        if _local(el.tag) == "path":
            d = _attrs(el).get("pathData")
            if d is not None:
                out[d] = (attrs, m)
        for ch in el:
            walk(ch, m, attrs)

    walk(ET.parse(path).getroot(), IDENT, {})
    return out


def close(x, y):
    return abs(x - y) <= TOL * max(1.0, abs(y))


full_svg_file, svg_file, vd_file = sys.argv[1], sys.argv[2], sys.argv[3]
full_svg = parse_svg(full_svg_file)
svg = parse_svg(svg_file)
vd = parse_vd(vd_file)
if not full_svg or not svg or not vd:
    print(
        f"ERROR: no glyph paths found (app_icon.svg={len(full_svg)}, "
        f"foreground.svg={len(svg)}, drawable={len(vd)}); "
        "cannot verify transforms",
        file=sys.stderr,
    )
    sys.exit(1)
missing = ({k for k in full_svg} ^ {k for k in svg}) | ({k for k in svg} ^ {k for k in vd})
if missing:
    print("ERROR: glyph path data present in only some of the files:", file=sys.stderr)
    for d in sorted(missing):
        print(f"  {d[:60]}...", file=sys.stderr)
    sys.exit(1)
bad = 0
for d in sorted(svg):
    full_chain, _ = full_svg[d]
    chain, m_svg = svg[d]
    attrs, m_vd = vd[d]
    if full_chain != chain:
        print(
            f"ERROR: transform association drift for glyph {d[:40]}... "
            "(path->transform mapping differs between the SVGs)",
            file=sys.stderr,
        )
        print(f"  app_icon.svg:   {full_chain or '(identity)'}", file=sys.stderr)
        print(f"  foreground.svg: {chain or '(identity)'}", file=sys.stderr)
        bad += 1
        continue
    for i, name in enumerate("abcdef"):
        if close(m_svg[i], m_vd[i]):
            continue
        print(
            f"ERROR: transform drift for glyph {d[:40]}...: matrix[{name}] "
            f"svg={m_svg[i]:.6f} != drawable={m_vd[i]:.6f}",
            file=sys.stderr,
        )
        print(f"  svg transform chain: {chain or '(identity)'}", file=sys.stderr)
        print(
            "  drawable group: "
            f"translateX={attrs.get('translateX', '0')} "
            f"translateY={attrs.get('translateY', '0')} "
            f"scaleX={attrs.get('scaleX', '1')} "
            f"scaleY={attrs.get('scaleY', '1')}",
            file=sys.stderr,
        )
        bad += 1
        break
if bad:
    print(f"ERROR: {bad} glyph(s) drifted (total {len(svg)})", file=sys.stderr)
    sys.exit(1)
print(
    "OK: glyph path->transform association matches across the SVGs, and "
    f"{len(svg)} glyph transforms match the VectorDrawable ("
    f"{vd_file.split('/')[-1]})"
)
PYEOF
}
verify_transform_consistency

# Background color: colors.xml must carry the brand seed teal.
grep -q 'ic_launcher_background">#009688<' "$RES_DIR/values/colors.xml" \
  || die "values/colors.xml: ic_launcher_background is not #009688 (brand seed)"

# ---------------------------------------------------------------------------
# 2. Safe-zone verification (best-effort): the glyph must stay inside the
#    33dp-radius centered circle of the 108dp canvas (adaptive-icon spec).
#    Recorded baseline for the current glyph (measured at 192px): 31.02dp.
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
  verify_safe_zone "$tmpdir/xxxhdpi.png" "legacy raster (check mode)"
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
