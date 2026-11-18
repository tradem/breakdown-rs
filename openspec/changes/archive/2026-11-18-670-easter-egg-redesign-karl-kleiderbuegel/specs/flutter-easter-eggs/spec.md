<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# flutter-easter-eggs

## MODIFIED Requirements

### Requirement: Karl Kleiderbügel Assistant in the AI Import View
The AI Import screens (`lib/features/ai_import/`) SHALL host a single
Easter egg: the **Karl Kleiderbügel** assistant (renamed from "Karl
Klammer" in issue #670; the persisted prefs key migrates once from
`easter_eggs.karl_klammer` to `easter_eggs.karl_kleiderbuegel` carrying
the stored value over, removing the old key; an explicit post-rename
choice always wins). The figure SHALL be drawn as a hand-ported
[CustomPainter] of the **approved user-drawn SVG artwork** (issue #670):
a classic wire-hanger silhouette with rounded triangle corners, a wire
twist at the neck, an inner strut below the apex, a wide sweeping hook
opening to the left, and an expressive face (big outlined eyes, bold
brows, open mouth), rendered with a 4-stop metal gradient and glint
lines. The approved artwork's fixed palette SHALL live in one documented
palette block (decision D3 — approved-artwork exception, like the
launcher icon); no color literal outside it. The SVG's `feDropShadow`
face filter SHALL be rebuilt Flutter-natively (blurred underlay) or
dropped — the decision SHALL be documented (decision D2: rebuilt). The
figure SHALL keep the #614/#615 motion contracts unchanged (five poses
with per-pose motion periods, a deterministic blink window, single
injected phase; no wall clock, no randomness), SHALL be visible ONLY
while the Easter-eggs toggle is enabled (immediate residue-free
disappearance), SHALL be non-modal and tap-dismissible, SHALL use
deterministic triggers only, SHALL make no network calls and no
user-level event tracking, SHALL be accessible, and SHALL honor the
system "remove animations" setting (static pose).

#### Scenario: Renamed everywhere with value migration
- **WHEN** the app boots after the update on a device that has a stored
  value under the old `easter_eggs.karl_klammer` key.
- **THEN** the value is carried over to `easter_eggs.karl_kleiderbuegel`,
  the old key is removed, and an explicit post-rename choice is never
  overwritten.

#### Scenario: Approved artwork rendering
- **WHEN** the figure is rendered in either theme (light or dark).
- **THEN** it shows the approved hanger artwork (wire twist, inner strut,
  metal gradient, glint lines, expressive face) with goldens protecting
  both themes; dev-time the painter output was pixel-compared against a
  reference render of the approved SVG.

#### Scenario: Motion contracts preserved
- **WHEN** widget tests drive the figure with `animate: true`.
- **THEN** the pose periods, phase continuity at the cycle boundary, and
  the deterministic blink window are unchanged from #614/#615, and
  `remove animations` renders the static pose with no controller running.

### Requirement: Deja-vu Cat Splash Egg (October-only)
The Deja-vu Cat SHALL render the **approved Ghibli-inspired black-cat
artwork** (issue #670): a seated cat with a big head, large alert
camera-facing eyes and the tail wrapped around the front paws, drawn with
a near-black radial fur gradient and a soft blue-grey rim light so the
silhouette stays readable on light AND dark surfaces. The artwork's fixed
palette SHALL live in one documented palette block (decision D3). The
October gate, the per-egg switch, the walk/travel math, the déjà-vu
glance beat (expressed as head tilt + pupil shift), the pause-damped walk
bob, the static phase under "remove animations", and the discoverability
surfaces of #640 SHALL remain unchanged.

#### Scenario: Approved cat artwork in both themes
- **WHEN** the cat renders on a hosting surface in light and dark themes.
- **THEN** the approved seated-cat artwork is visible and readable in
  both (goldens), with the walk/travel/glance contracts of #615/#640
  unchanged.
