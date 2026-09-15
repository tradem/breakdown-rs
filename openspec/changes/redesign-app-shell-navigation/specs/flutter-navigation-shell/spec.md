<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## ADDED Requirements

### Requirement: Adaptive Four-Tab Navigation Shell
The app SHALL host all post-login content inside a navigation shell
with four destinations — Season (home), Planen (hierarchy), Kleidung
(costume domains), Mehr (reports, imports, settings) — rendering
adaptive navigation per M3 window size class: `NavigationBar` below
600dp, `NavigationRail` from 600dp, and permanent `NavigationDrawer`
from 840dp. Every destination SHALL render a visible text label;
icon-only destinations are forbidden. The shell SHALL appear only for
a resolved authenticated session (AuthGate contract unchanged).

#### Scenario: Phone portrait (default Android)
- **WHEN** the app runs on a compact window (< 600dp wide).
- **THEN** navigation renders as a bottom `NavigationBar` with four
  labeled destinations and the Season tab selected first.

#### Scenario: Tablet or landscape medium window
- **WHEN** the window width is between 600 and 839dp.
- **THEN** navigation renders as a `NavigationRail` beside the content.

#### Scenario: Desktop-class expanded window
- **WHEN** the window width is ≥ 840dp.
- **THEN** navigation renders as a permanent `NavigationDrawer`.

#### Scenario: Signed-out session
- **WHEN** the auth session resolves to signed-out or restore is
  pending.
- **THEN** no shell or tab content renders (login/splash per the
  AuthGate contract).

### Requirement: Tab State Preservation and Back Behavior
Each tab SHALL preserve its own navigation position while the user
switches tabs. System back SHALL pop within the active tab's stack
first; when the active tab's stack is at its root, back SHALL NOT
switch tabs (no multi-hop pops), and at the root of the initial tab
it requests app exit per platform convention.

#### Scenario: Switching tabs preserves position
- **WHEN** the user drills into Season → Block → Episode in Planen,
  switches to Kleidung, and returns to Planen.
- **THEN** Planen restores its previous Episode screen position.

#### Scenario: Back does not hop tabs
- **WHEN** the user presses system back while on a non-root screen of
  tab B after arriving from tab A.
- **THEN** the back press pops tab B's stack to its root; it does not
  return to tab A.

### Requirement: Costume Domains Behind the Kleidung Tab
Costumes, characters, and their detail screens SHALL be reachable as
first-class content of the Kleidung tab scoped to the active season,
without requiring a prior navigation through the season row's icon
buttons. The season-scoped costume/character list screens retain their
existing controllers, repositories, AUTHZ-GATE comments, and
optimistic-reconciliation behavior; only their entry points change.

#### Scenario: Reaching costumes without season-row icons
- **WHEN** the user taps the Kleidung tab with an active season
  selected.
- **THEN** the season's costume list renders with the same
  repository-backed content as the previous CostumesScreen, reachable
  without any icon-button tooltip knowledge.

#### Scenario: No active season
- **WHEN** the user opens the Kleidung tab and no season is selected
  or none exists.
- **THEN** the tab renders a season-selection empty state with a
  create/setup call to action linking to the Season tab, not an error.

### Requirement: Accessible Labeled Destinations
All four destinations SHALL expose semantic labels and tooltips
matching the glossary (`docs/design/glossary.md`), and the shell
SHALL pass accessibility checks for touch target size and semantic
traversal order across all three navigation morphologies.

#### Scenario: Screen reader traversal
- **WHEN** a screen reader traverses the shell in compact and
  expanded morphologies.
- **THEN** each destination is announced with its visible label
  (e.g. "Season, Tab 1 of 4") and touch targets meet 48×48dp.
