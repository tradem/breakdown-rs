<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

## ADDED Requirements

### Requirement: Status-Bar Safe-Area Top Bar

The shell's sticky top bar SHALL be inset by the `MediaQuery` view padding
in every navigation morphology (compact bottom navigation bar, medium rail,
expanded drawer), so that no shell or view content renders beneath the
system status bar on Android. The inset SHALL be applied once, by the shell
top bar itself.

#### Scenario: Android status bar does not overlap the top bar
- **WHEN** the shell renders on a device/window with a non-zero top view
  padding (status bar).
- **THEN** the top bar's first row starts at or below the status-bar
  height, in all three morphologies.

#### Scenario: No inset when there is no status bar
- **WHEN** the shell renders with a zero top view padding.
- **THEN** the top bar starts at `y = 0` with no extra spacing.

### Requirement: Sticky Two-Row Shell Top Bar

The shell SHALL own a two-row sticky top bar above the view content in
every morphology. Row 1 SHALL carry the profile affordance at its far left
followed by the scope pills. Row 2 SHALL carry the active destination's
visible title, the hierarchy breadcrumb (`LocationStrip`) and the search
affordance. The top bar SHALL stay pinned above the view content across
destination switches, and the destination roots SHALL NOT render their own
app bar (the shell view bar carries the title). The profile and search
affordances SHALL open inside the active destination's nested navigator.

#### Scenario: Row composition
- **WHEN** the shell renders for a resolved authenticated session.
- **THEN** row 1 shows the profile affordance left-most and the scope pills
  to its right, and row 2 shows the active destination's title, the
  breadcrumb (when the active destination has a pushed location) and the
  search affordance.

#### Scenario: View title follows the active destination
- **WHEN** the user switches from the Cast destination to the Script
  destination.
- **THEN** the view bar's title changes from the Cast label to the Script
  label.

#### Scenario: No destination app bar
- **WHEN** a destination root is visible.
- **THEN** no destination-owned app bar renders; the shell view bar is the
  only title surface.

#### Scenario: Search opens inside the active destination
- **WHEN** the user taps the search affordance.
- **THEN** the OmniSearch surface pushes on the active destination's nested
  navigator.

### Requirement: Scope Pill Visual Hierarchy

The three scope levels SHALL render as fully rounded pills. A pill whose
scope is set SHALL be filled with a level-specific container color
(season → primary container, block → secondary container, episode →
tertiary container) so the three levels are visually distinguishable; a
pill whose scope is unset SHALL render a neutral fill with a "… wählen"
label that opens the level's picker. Pill color SHALL never be the sole
carrier of meaning: the pill's visible label names the level and its state.
The pills SHALL keep the `season-scope-chip`, `active-scope-chip` and
`active-episode-chip` keys and a touch target of at least 48×48dp.

#### Scenario: Selected level is color-highlighted
- **WHEN** a season, a block scope and an episode scope are all set.
- **THEN** each of the three pills is filled with its own level container
  color and shows its level label.

#### Scenario: Unset level is neutral and actionable
- **WHEN** a season is active but no block scope is set.
- **THEN** the block pill renders with the neutral fill and the localized
  "Block wählen" label, and tapping it opens the block picker for the
  active season.

## MODIFIED Requirements

### Requirement: Season and Block Scope Surface

The shell's first top-bar row SHALL render the three scope pills
(Season · Block · Episode) with prerequisite-aware visibility: the season
pill is always present, the block pill appears once a season is active or a
block scope is set, and the episode pill appears once a block scope is set
or an episode scope is set. An unset level renders a neutral pill that
opens its picker; a set level is color-highlighted (see "Scope Pill Visual
Hierarchy"). Tapping the season pill SHALL open the season scope picker.
Setting a season SHALL source the season id exclusively from the season
read DTO the user acted on and SHALL persist the reference under the
current session scope (unchanged CQRS-boundary and session-scoped
persistence rules). The block and episode pills SHALL keep their
unknown-block / foreign-season narratives and their pickers.

#### Scenario: Season pill is always present
- **WHEN** the app starts and no season and no block scope are set.
- **THEN** the top bar renders the neutral season pill, and tapping it
  opens the season scope picker.

#### Scenario: Active season highlights the season pill
- **WHEN** a season is active and no block scope is set.
- **THEN** the season pill renders with the season's label and the season
  highlight color, and the block pill renders neutral and opens the block
  picker.

#### Scenario: Season and block scope render together
- **WHEN** a season and a block scope are both set for the same season.
- **THEN** both pills render highlighted, and the block pill keeps its
  existing block-picker behaviour including the foreign-season narrative.

#### Scenario: Picking a season from the picker
- **WHEN** the user taps a season row in the season scope picker.
- **THEN** the picker pops and that season becomes the active season for
  all three destinations.

### Requirement: Task-Oriented View Content

Each destination SHALL render a task-oriented surface: **Cast** hosts the
season-scoped character and costume surfaces with the costume-category
vocabulary and the fundus entry reachable from the Cast view's own toolbar
below the shell view bar, **Script** hosts the season's chronologically
numbered scene overview, **Schedule/Dispo** hosts the season's shooting
days. The former Season, Planen, Kleidung and Mehr tab roots SHALL NOT
exist as destinations; their content SHALL be reachable through the season
scope picker (season management, production management) and the
shell-owned profile affordance.

#### Scenario: Cast view surfaces characters, costumes and categories
- **WHEN** the user opens the Cast destination with an active season.
- **THEN** the view offers a switch between the season-scoped characters
  list and costumes list, and a toolbar action opens the season-scoped
  costume-category screen for that season.

#### Scenario: Script view renders the chronological scene overview
- **WHEN** the user opens the Script destination with an active season.
- **THEN** the view lists that season's scenes merged across its episodes
  and ordered by `scene_number`, and tapping a row pushes the scene
  detail screen with that scene read DTO as navigation context.

#### Scenario: Script view degrades honestly on a partial fan-out
- **WHEN** one episode of the active season fails to load its scenes, or one
  block fails to load its episode list.
- **THEN** the successfully loaded scenes still render together with a
  visible partial-load notice naming the failed level; the missing scenes
  are never silently presented as the season's complete script.

#### Scenario: Script view without an active season
- **WHEN** the user opens the Script destination and no season is active.
- **THEN** the view renders a season-selection empty state whose call to
  action opens the season scope picker — not an error.

#### Scenario: Schedule/Dispo view renders the shooting days
- **WHEN** the user opens the Schedule/Dispo destination with an active
  season.
- **THEN** the season's shooting days render in day order with their
  existing labelled reports entry unchanged.

### Requirement: Per-View Profile Affordance

The shell's top bar SHALL render exactly one profile action, left-most in
its first row, that opens a profile menu with the authenticated identity
(non-interactive), the app information dialog, the settings screen and
sign-out. The destination roots SHALL NOT carry their own profile action.
The costume-category vocabulary SHALL NOT appear in the profile/settings
surface. Sign-out SHALL continue to run the session-reset coordinator.

#### Scenario: Profile menu content
- **WHEN** the user opens the profile action.
- **THEN** the menu offers the signed-in identity, "Über die App",
  "Einstellungen" and "Abmelden", and no costume-category entry.

#### Scenario: One profile action across destinations
- **WHEN** the user switches between the three destinations.
- **THEN** exactly one profile action is present in the shell top bar, and
  no destination root renders its own.

#### Scenario: Sign-out from the profile menu
- **WHEN** the user taps "Abmelden" in the profile menu.
- **THEN** the session-reset coordinator runs and the shell disappears with
  the session.
