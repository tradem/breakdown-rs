<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-navigation-shell Delta — issue #991

## ADDED Requirements

### Requirement: The compact bottom bar is a translucent glass surface

The compact morphology's `NavigationBar` SHALL render as a translucent, blurred
surface that the destination content scrolls UNDER, and SHALL NOT paint an
opaque band (no `surfaceContainer` fill, no shadow line, no surface-tint
overlay). Making the transparency visible SHALL require all three of:

1. the bar paints nothing opaque — its background is a translucent tint and its
   elevation, shadow color and surface tint are zero/transparent;
2. the compact `Scaffold` sets `extendBody: true`, so the body is laid out
   behind the bar;
3. the body's bottom inset equals the bar's PAINTED height — the bar's own
   height plus the system bottom inset its internal `SafeArea` adds — so no
   list row of any destination hides under the bar.

The bar's background MAY be a plane lifted slightly off the plain surface role,
derived per brightness from the scheme (never a fixed grey), and a
`BackdropFilter` MAY blur the content behind it. The selected-indicator pill and
the label/icon colors SHALL stay opaque. The bar's semantics (the `Tab N of 3`
traversal, the per-destination keys, the 48 dp touch targets) SHALL NOT change.

#### Scenario: Content scrolls under the bar on every destination

- **WHEN** a compact-window user scrolls a destination's list (Cast, Script or
  Schedule).
- **THEN** rows pass behind the bar and are visible through its tint in both the
  light and the dark theme, while the bar itself keeps no opaque band.

#### Scenario: The last row stays reachable above the bar

- **WHEN** the user scrolls a destination to its end, including on a device with
  a gesture-navigation bottom inset.
- **THEN** the last row comes to rest above the bar, and the reserved space is
  the bar's painted height (its own height plus the system inset) — never a
  hardcoded bar height.

#### Scenario: The plus action keeps one reservation, not two

- **WHEN** the Script destination — the only one that renders the plus action —
  is compared with Cast and Schedule.
- **THEN** Script reserves the plus action's docked band ON TOP of the bar inset
  (the last row clears the FAB), Cast and Schedule reserve only the bar inset
  (no dead strip), and the per-destination marker that issue #823 introduced is
  present on exactly the destinations that render the action.

#### Scenario: An open keyboard makes the bar opaque

- **WHEN** a keyboard is open (a non-zero bottom view inset).
- **THEN** the bar paints its plane opaque and drops the backdrop blur, so no
  content shows through it, and its labels/indicator stay readable.

#### Scenario: The medium and expanded morphologies are unaffected

- **WHEN** the window is at least 600 dp wide.
- **THEN** the shell renders its `NavigationRail` / `NavigationDrawer` with no
  glass surface and no extended body.

#### Scenario: Label and icon contrast survive the worst-case backdrop

- **WHEN** the bar is composited over the worst-case blurred backdrop (white in
  the light theme, black in the dark theme).
- **THEN** label text reaches at least 4.5:1 contrast and icons / the indicator
  indication at least 3:1, asserted by a unit test on the derived colors without
  a shader-dependent golden.
