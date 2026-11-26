<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 991 — The compact bottom bar is a translucent glass surface

## Why

On the compact morphology the bottom navigation bar is the single largest
permanent opaque block on screen — an ~80 dp `surfaceContainer` band over
content that is frequently visual (costume/continuity photos, scene lists,
day boards). It permanently eats the vertical space it occupies and reads as
a separate chrome strip even though the destinations are the content.

Issue #991 asks for the Spotify / Apple-Music pattern instead: content scrolls
*under* a blurred, lightly tinted bar that stays resident. On `main` this is
both small and well-localised — there is exactly one render site
(`app_shell.dart`, compact `Scaffold.bottomNavigationBar`) and **zero**
`BackdropFilter` anywhere in `lib/` — which is why it deserves a decided,
token-backed implementation rather than an inline `Colors.transparent` plus a
magic alpha: it is the client's **first glass surface**, and the pattern will
be copied.

Three sub-decisions the issue left open were settled with the user before
implementation:

1. **Blur ships with the transparency** (not Step A alone, no runtime flag):
   the transparent-only bar still leaves the content's under-scroll invisible
   in the damped way the effect needs, and the blur is the actual product ask.
2. **The tint is a slightly lifted plane**, not a pure `scheme.surface` alpha:
   a real glass surface reads as its own plane.
3. **The bar falls back to opaque while the keyboard is open**: a translucent
   bar over live text fields reads as a hole in the layout.

## What changes

- **Tokens** (`design/tokens/component.json`): a new
  `component.navigationBar` group with the four decisions no primitive owns —
  `height` (80 dp), `tintAlpha` (0.72), `planeLiftAlpha` (0.06) and
  `blurSigma` (12 px). The tint *color* is not a token: it is derived per
  brightness from `scheme.surface` + `scheme.surfaceTint`, because a fixed grey
  would read as a hole in dark mode.
- **Token format**: the DTCG `number` type becomes supported by
  `design/validate-tokens.mjs` (an alpha/ratio has no dimension counterpart).
  This is the second relaxation of the foundation's type set after #838's
  dimension aliases, and it is recorded here for the same reason.
- **Theme** (`lib/design/theme.dart`): a `NavigationBarThemeData` that paints
  **nothing opaque** — token height, translucent tint, `elevation: 0`,
  `shadowColor`/`surfaceTintColor` transparent. Indicator and label/icon colors
  stay M3 defaults (opaque, and the ones whose contrast is measured).
- **New consumer seam** (`lib/design/navigation_bar_metrics.dart`): the single
  place the token values are read and the two colors composed, mirroring
  `HeaderMetrics` for the header.
- **New component** (`lib/design/components/glass_bottom_bar.dart`): the
  `ClipRect` + `BackdropFilter` surface, dropping the filter and painting the
  same plane opaque while the keyboard is open.
- **Shell** (`lib/features/shell/app_shell.dart`): the compact `Scaffold` gets
  `extendBody: true` (without it transparency only reveals the Scaffold
  background); the bar slot renders the glass surface; the plus action's
  80 dp clearance moves from a Column band into the body's bottom
  `MediaQuery` inset, because a band shrinks the viewport and would hide the
  glass. The status-bar single-count seam (#824) also moves into the body,
  where the Scaffold's `extendBody` padding is visible.
- **Docs**: `docs/design/screens/navigation-shell.md` (compact wireframe +
  Components row), `design/tokens/README.md` (the new group + the `number`
  type), the `design-tokens-dtcg` skill.

## Decisions

### D1 — `extendBody` is the only way to make transparency visible

Without it the body stops above the bar, so a transparent bar reveals the
`Scaffold`'s own background and looks like a plain tinted strip. With it the
bar has real content behind it. `Scaffold` also then hands the body a
`MediaQuery` bottom padding equal to the **laid-out** bar height, which is
exactly the inset the content needs — the framework's own arithmetic, not ours.

### D2 — The reservation is one derived inset, not a Column band

`NavigationBar` wraps itself in a `SafeArea`, so its painted height is
`height + viewPadding.bottom` (80 dp on 3-button nav, 80 + inset on gesture
nav). `Scaffold(extendBody: true)` computes that for the body; the shell adds
only the plus action's 80 dp band on top, on the same predicate that renders
the FAB (#823). Scrollables turn a null `padding` into exactly that
`MediaQuery` padding (`BoxScrollView.buildSlivers`), so the last row of every
destination stays reachable **while** content scrolls under the bar. A Column
band would reserve the same space but shrink the viewport, making the glass
invisible — the collision the issue describes.

`#823`'s keyed marker (`shell-plus-fab-clearance`) survives unchanged in
presence semantics: it is rendered on exactly the destinations that carry the
plus action, and now has no extent because the reservation lives in the inset.

### D3 — The tint carries the contrast budget, the blur only the effect

Pure blur over costume/continuity photography destroys label and indicator
contrast. `tintAlpha 0.72` leaves 28 % of the backdrop visible (that is what
makes the bar read as glass) while keeping M3's label colors ≥ 4.5:1 and the
icons/indicator ≥ 3:1 against the **worst-case** blurred backdrop (white in
light mode, black in dark). `test/design/navigation_bar_metrics_test.dart`
measures exactly that; a future token change that breaks it fails a test.

### D4 — Two states, one color decision

The keyboard fallback paints the plane **opaque** behind the bar. Because the
bar's own tint is that same plane at `tintAlpha`, compositing the two yields
exactly the plane — so the fallback needs no second color, no second token and
no call-site alpha. The blur is dropped with it (an opaque bar has nothing to
blur, and the filter is the shell's most expensive widget).

### D5 — Blend the plane from scheme roles, not from a fixed color

`planeLiftAlpha` moves the surface toward `scheme.surfaceTint`, which
`ColorScheme.fromSeed` derives **per brightness**. A hardcoded grey (or a
`surfaceContainer` role) would either wash out light mode or read as a hole in
dark mode.

## Alternatives rejected

- **Step A only (transparent, no blur).** Cheap and artifact-free, but the
  bar then reads as a plain transparent band; the issue's title is the glass
  bar, and the user chose both together.
- **A runtime blur flag (dart-define / settings).** A second code path and a
  second set of tests for a degradation that is already a one-line change
  (`blurSigma` → drop the wrapper). Documented as the fallback instead.
- **`ElevationOverlay.applySurfaceTint` for the plane lift.** Reuses M3's
  elevation-tint math, but its internal alpha curve moves between Flutter
  versions — a golden-stability hazard for a value we can state as one number.
- **Keeping the plus-action Column band.** Would stack a second 80 dp
  reservation on top of the bar's and shrink the viewport (see D2).
- **`MediaQuery.removePadding(removeTop: true)` at the old seam.** It rebuilt
  the MediaQuery from the context *above* the Scaffold, discarding the
  `extendBody` bottom padding. The status-bar single-count rule moved into the
  body, around the tab content only (the top bar keeps its own inset).

## Impact

- `design/tokens/component.json`, `design/validate-tokens.mjs`,
  `frontend-flutter/lib/design/gen/design_tokens.g.dart` (regenerated,
  74 → 78 tokens).
- `frontend-flutter/lib/design/theme.dart`,
  `lib/design/navigation_bar_metrics.dart` (new),
  `lib/design/components/glass_bottom_bar.dart` (new),
  `lib/features/shell/app_shell.dart`.
- Tests: `test/design/navigation_bar_metrics_test.dart` (new),
  `test/design/components/glass_bottom_bar_test.dart` (new, incl. two goldens
  over scrolled content), `test/features/shell/app_shell_test.dart`
  (glass/extendBody/inset assertions). Re-baselined goldens:
  `app_shell_compact_{light,dark}.png`,
  `app_shell_pushed_header_status_bar.png`, `account_drawer_{light,dark}.png`
  (the last two render the shell, and the bar's surface is in frame).
- Docs: `docs/design/screens/navigation-shell.md`,
  `design/tokens/README.md`, `.pi/skills/design-tokens-dtcg/SKILL.md`,
  `CHANGELOG.md`, `pubspec.yaml` version bump. `docs/design/glossary.md`
  needs no new term: the treatment gets no user-visible name (the destination
  labels, icons and the "Navigation" vocabulary are unchanged).

## Out of scope

- Medium/expanded morphologies (`NavigationRail` / `NavigationDrawer`) — a
  rail has no "content scrolling under it" story.
- The shell top bar and the offline pill: a glass *pair* (top + bottom) is a
  separate decision.
- iOS/macOS blur tuning (Android first).
- Any navigation-model change (destination count, bar height semantics).
