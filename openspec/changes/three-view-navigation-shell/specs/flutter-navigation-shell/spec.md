<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

## ADDED Requirements

### Requirement: Adaptive Three-View Navigation Shell
The app SHALL host all post-login content inside a navigation shell with
exactly three destinations in this order — **Cast** (0), **Script** (1),
**Schedule/Dispo** (2) — rendering adaptive navigation per M3 window size
class: `NavigationBar` below 600dp, `NavigationRail` from 600dp and
permanent `NavigationDrawer` from 840dp. Every destination SHALL render a
visible text label with the glossary icon (`face`/`menu_book`/
`calendar_month`); icon-only destinations are forbidden. The shell SHALL
appear only for a resolved authenticated session (AuthGate contract
unchanged). The destination keys SHALL be `shell-destination-0`,
`shell-destination-1` and `shell-destination-2`, and the shell controller
SHALL expose the tab-index constants `kCastTabIndex`,
`kScriptTabIndex` and `kScheduleTabIndex` — the former
`kSeasonTabIndex`/`kPlanenTabIndex`/`kKleidungTabIndex`/`kMehrTabIndex`
SHALL no longer exist.

#### Scenario: Phone portrait (default Android)
- **WHEN** the app runs on a compact window (< 600dp wide) with an
  authenticated session.
- **THEN** navigation renders as a bottom `NavigationBar` with exactly
  three labeled destinations (Cast, Script, Schedule/Dispo) and the Cast
  destination selected first.

#### Scenario: Tablet or landscape medium window
- **WHEN** the window width is between 600 and 839dp.
- **THEN** navigation renders as a `NavigationRail` beside the content
  with the same three destinations and visible labels.

#### Scenario: Desktop-class expanded window
- **WHEN** the window width is ≥ 840dp.
- **THEN** navigation renders as a permanent `NavigationDrawer` listing
  the same three destinations.

#### Scenario: Signed-out session
- **WHEN** the auth session resolves to signed-out or restore is pending.
- **THEN** no shell or destination content renders (login/splash per the
  AuthGate contract).

#### Scenario: Out-of-range selection is rejected
- **WHEN** the shell controller is asked to select a destination index
  below `0` or above `kScheduleTabIndex`.
- **THEN** the selected destination does not change.

### Requirement: Task-Oriented View Content
Each destination SHALL render a task-oriented surface: **Cast** hosts the
season-scoped character and costume surfaces with the costume-category
vocabulary reachable from its app bar, **Script** hosts the season's
chronologically numbered scene overview, **Schedule/Dispo** hosts the
season's shooting days. The former Season, Planen, Kleidung and Mehr tab
roots SHALL NOT exist as destinations; their content SHALL be reachable
through the season scope picker (season management, production management)
and the per-view profile affordance.

#### Scenario: Cast view surfaces characters, costumes and categories
- **WHEN** the user opens the Cast destination with an active season.
- **THEN** the view offers a switch between the season-scoped characters
  list and costumes list, and an app-bar action opens the season-scoped
  costume-category screen for that season.

#### Scenario: Script view renders the chronological scene overview
- **WHEN** the user opens the Script destination with an active season.
- **THEN** the view lists that season's scenes merged across its episodes
  and ordered by `scene_number`, and tapping a row pushes the scene
  detail screen with that scene read DTO as navigation context.

#### Scenario: Script view degrades honestly on a partial fan-out
- **WHEN** one episode of the active season fails to load its scenes.
- **THEN** the successfully loaded scenes still render together with a
  visible partial-load notice; the missing episode's scenes are never
  silently presented as the season's complete script.

#### Scenario: Script view without an active season
- **WHEN** the user opens the Script destination and no season is active.
- **THEN** the view renders a season-selection empty state whose call to
  action opens the season scope picker — not an error.

#### Scenario: Schedule/Dispo view renders the shooting days
- **WHEN** the user opens the Schedule/Dispo destination with an active
  season.
- **THEN** the season's shooting days render in day order with their
  existing labelled reports entry unchanged.

### Requirement: Season and Block Scope Surface
The shell's context bar SHALL render a season scope chip alongside the
existing block scope chip whenever the respective scope is set, and SHALL
be hidden entirely when neither has anything to say. Tapping the season
chip SHALL open a season scope picker. Setting a season SHALL source the
season id exclusively from the season read DTO the user acted on and SHALL
persist the reference under the current session scope (unchanged
CQRS-boundary and session-scoped persistence rules).

#### Scenario: No scope renders no bar
- **WHEN** the app starts and neither a season nor a block scope is set.
- **THEN** the shell context bar renders nothing and the view content
  starts directly below it.

#### Scenario: Active season renders the season chip
- **WHEN** a season is active and no block scope is set.
- **THEN** the context bar renders the season chip with the season's
  label, and tapping it opens the season scope picker.

#### Scenario: Season and block scope render together
- **WHEN** a season and a block scope are both set for the same season.
- **THEN** the context bar renders both chips, and the block chip keeps its
  existing block-picker behaviour including the foreign-season narrative.

#### Scenario: Picking a season from the picker
- **WHEN** the user taps a season row in the season scope picker.
- **THEN** the picker pops and that season becomes the active season for
  all three destinations.

### Requirement: Season Scope Picker Destinations
The season scope picker SHALL offer, besides the season rows: a season
management entry pushing the seasons overview screen, and a production
management entry pushing the production overview screen (block/episode
spine, AI-import entry and active AI-import jobs row).

#### Scenario: Season management from the picker
- **WHEN** the user taps "Saisonen verwalten" in the season scope picker.
- **THEN** `SeasonsScreen` pushes on the active destination's nested
  navigator and its create action remains available.

#### Scenario: Production management from the picker
- **WHEN** the user taps "Produktion verwalten" in the season scope picker.
- **THEN** the production overview screen pushes on the active
  destination's nested navigator and lists the active season's blocks,
  the AI-import entry and the active-jobs row while a job needs
  attention.

### Requirement: Per-View Profile Affordance
Each of the three destination roots SHALL render one app-bar action that
opens a profile menu with the authenticated identity (non-interactive),
the app information dialog, the settings screen and sign-out. The
costume-category vocabulary SHALL NOT appear in the profile/settings
surface. Sign-out SHALL continue to run the session-reset coordinator.

#### Scenario: Profile menu content
- **WHEN** the user opens the profile action on any destination.
- **THEN** the menu offers the signed-in identity, "Über die App",
  "Einstellungen" and "Abmelden", and no costume-category entry.

#### Scenario: Sign-out from the profile menu
- **WHEN** the user taps "Abmelden" in the profile menu.
- **THEN** the session-reset coordinator runs and the shell disappears with
  the session.

### Requirement: Accessible Labeled Destinations
All three destinations SHALL expose semantic labels and tooltips matching
the glossary, announced as "<label>, Tab N of 3", and the shell SHALL pass
accessibility checks for touch target size and semantic traversal order
across all three navigation morphologies.

#### Scenario: Screen reader traversal
- **WHEN** a screen reader traverses the shell in compact and expanded
  morphologies.
- **THEN** each destination is announced with its visible label
  (e.g. "Cast, Tab 1 of 3") and touch targets meet 48×48dp.
