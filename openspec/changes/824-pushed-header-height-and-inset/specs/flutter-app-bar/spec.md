<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-app-bar Delta — issue #824

## ADDED Requirements

### Requirement: One Tokenized Header Role

Every pushed screen's header SHALL be the shared `BreakdownAppBar` (a text
form and a composite `BreakdownAppBar.custom` form). Its height SHALL come from
the theme's `appBarTheme.toolbarHeight`, derived in `HeaderMetrics` from the
`typography.lineHeight.titleLarge` and spacing tokens and clamped up to the
Material interactive-dimension minimum; its title style SHALL come from
`appBarTheme.titleTextStyle` (the type scale's `titleLarge`). No screen SHALL
declare a `toolbarHeight`, an `AppBarTheme` override, or its own title
`TextStyle` for a header.

#### Scenario: A new pushed screen is added
- **WHEN** a screen renders a back-arrow header.
- **THEN** it uses `BreakdownAppBar`, and its rendered height equals
  `HeaderMetrics.toolbarHeight` without the screen passing a height.

#### Scenario: A screen tries a different header height
- **WHEN** a review or test finds a `toolbarHeight` literal in a screen.
- **THEN** it is rejected; the height is a theme/token concern.

### Requirement: Single-Line Ellipsized Titles

A text header title SHALL render on exactly one line with a trailing ellipsis
(`maxLines: 1`, `overflow: TextOverflow.ellipsis`, `softWrap: false`), so the
header can never be taller than its spec and long text is truncated instead of
clipped. A composite title SHALL own its own overflow rule.

#### Scenario: A scene summary is used as the header title
- **WHEN** a scene's summary is longer than the header width.
- **THEN** the header shows it on one line ending in an ellipsis, and the full
  text remains available on the detail surface — nothing is clipped.

#### Scenario: Large text scale
- **WHEN** the app renders under `textScaler` 1.3 (the repo's a11y ceiling).
- **THEN** the header title still fits the bar and no overflow error is
  emitted.

### Requirement: The Status Bar Is Counted Exactly Once

The shell's top bar SHALL own the status-bar inset. The tab content below it
SHALL have the top inset removed at the shell seam, so a pushed screen's header
SHALL NOT apply the status-bar inset again. The header's top edge SHALL equal
the shell bar's bottom edge.

#### Scenario: A pushed header under a device status bar
- **WHEN** a screen is pushed onto a tab navigator on a device with a
  non-zero status bar.
- **THEN** the header's height is the toolbar height alone (no blank
  status-bar gap above it), and the total chrome above the body is the shell
  bar plus one toolbar.

#### Scenario: Regression guard
- **WHEN** a widget test sets `tester.view.padding`/`viewPadding` and pushes a
  screen inside the shell.
- **THEN** the header's rendered height is asserted against
  `HeaderMetrics.toolbarHeight` (not merely inspected by eye or by a
  zero-padding golden).

### Requirement: The Back Affordance Stays Accessible

The header's back affordance SHALL keep a touch target of at least 48 × 48
logical px and SHALL pop exactly one route. The reduced header height SHALL NOT
be achieved by shrinking the icon button.

#### Scenario: Back from a pushed screen
- **WHEN** the user taps the header's back arrow.
- **THEN** the route pops to the pushing screen, and the button's hit area is
  at least 48 × 48 logical px.

### Requirement: Status-Bar-Padded Golden Coverage

At least one golden SHALL render the shell with a status bar plus a pushed
header, so the single-inset rule is pinned visually as well as geometrically.
Screen goldens affected by the header height SHALL be re-baselined in the same
change.

#### Scenario: A screen golden is re-baselined
- **WHEN** the header height changes.
- **THEN** every affected screen golden is re-baselined in the same change and
  the diff is reviewed for clipping or a lost title line.
