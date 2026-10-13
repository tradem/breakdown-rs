<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

## ADDED Requirements

### Requirement: Sticky active-episode scope

The client SHALL track a sticky active-episode scope carrying the episode id
plus its block id, number and name, sourced from the `EpisodeView` the user
acted on (never a second projection lookup). The scope SHALL be set
synchronously before navigation at every episode-entry point (episode row →
scenes, the episode shooting-days entry, a Script scene row, a Schedule day
row), SHALL be changeable through the shell's episode chip picker, and SHALL
be cleared on sign-out and on a backend switch so a new identity never
inherits it. The scope SHALL be persisted per season, and a persistence
failure SHALL NOT break the in-memory scope.

#### Scenario: Entering an episode's scenes sets the scope
- **WHEN** the user taps a projected episode row
- **THEN** the active-episode scope is set to that episode before
  `ScenesScreen` is pushed

#### Scenario: Entering an episode's day board sets the scope
- **WHEN** the user taps the episode shooting-days entry, a Script scene row,
  or a Schedule day row
- **THEN** the active-episode scope is set to the episode carried by the
  acted-on DTO before the target screen is pushed

#### Scenario: Sign-out clears the scope
- **WHEN** the user signs out
- **THEN** the active-episode scope and its persisted document are cleared,
  and the next session starts with no episode scope

#### Scenario: A store failure does not break the scope
- **WHEN** persisting the scope fails
- **THEN** the in-memory scope still holds the picked episode and the
  failure is swallowed (best-effort persistence)

### Requirement: Episode chip and picker

The shell's context bar SHALL render an episode chip next to the season and
block chips whenever an active-episode scope is set, showing a visible
`Episode {n}` label (the episode name when present) with a glossary icon
reinforcing only. Tapping the chip SHALL open a picker listing the scope
block's episodes through the existing episode list seam; picking one SHALL
set the scope and pop. The chip SHALL be hidden when no scope is set. A scope
whose season differs from the currently navigated season SHALL say so instead
of presenting the foreign episode as if it applied.

#### Scenario: The chip is visible and labelled
- **WHEN** an active-episode scope is set
- **THEN** the context bar shows the episode chip with the episode's visible
  label and icon

#### Scenario: Changing the scope from the picker
- **WHEN** the user opens the chip's picker and picks another episode of the
  scope block
- **THEN** the active-episode scope becomes the picked episode and the
  picker pops

#### Scenario: No scope, no chip
- **WHEN** no active-episode scope is set
- **THEN** the context bar renders no episode chip

### Requirement: Context-sensitive quick-create entries

`shellQuickCreateActions` SHALL remain a data-driven factory. It SHALL accept
an optional active-episode scope: with no scope it SHALL return exactly the
existing context-free entries (KI-Import and the season setup wizard); with a
scope it SHALL add a "Neue Szene" and a "Neuer Drehtag" entry that push the
full-screen create pages for the scoped episode. The context-free entries
SHALL remain present in both states, and no entry SHALL be offered without a
scope to back it.

#### Scenario: No scope keeps the shipped list
- **WHEN** the quick-create sheet opens with no active-episode scope
- **THEN** it lists only the context-free entries (KI-Import, Season-Setup)

#### Scenario: A scope adds the two context entries
- **WHEN** the quick-create sheet opens with an active-episode scope
- **THEN** it lists "Neue Szene" and "Neuer Drehtag" for that episode
  alongside the context-free entries

#### Scenario: The context entries push full-screen create pages
- **WHEN** the user taps "Neue Szene" or "Neuer Drehtag"
- **THEN** the sheet pops and the corresponding full-screen create page is
  pushed for the scoped episode (never an embedded form, never a modal)

### Requirement: Full-screen create pages

The client SHALL provide a full-screen create page for scenes and one for
shooting days, each hosting the same form implementation the in-context FAB
sheets use. Each page SHALL dispatch the create command through the existing
episode-keyed controller and SHALL surface command failures through the same
command-error provider the list screens use. The command SHALL source its
`episode_id` from the page's episode scope.

#### Scenario: Creating a scene from the quick-create page
- **WHEN** the user submits a valid scene form on `CreateSceneScreen`
- **THEN** `POST /v1/scenes` dispatches for the page's episode and the page
  pops on success

#### Scenario: Command failure is surfaced
- **WHEN** the create command fails on a full-screen create page
- **THEN** the failure is rendered through the command-error surface keyed
  on the problem `code` (never a silently discarded error)

#### Scenario: Client AUTHZ gate before any network call
- **WHEN** the create page submits without a resolved authenticated session
- **THEN** no network request is issued and the denial is surfaced as an
  error value (a pending session restore disables, never denies)

### Requirement: Localization and glossary rows

Every new visible string (the two quick-create entries, their subtitles, the
episode chip label/tooltip and the picker copy) SHALL ship in the German
template and the English catalog, and each new affordance SHALL have a
glossary row naming its visible label, icon and copy key.

#### Scenario: German and English catalogs stay in parity
- **WHEN** the localization pipeline runs
- **THEN** the new keys exist in both `app_de.arb` and `app_en.arb` with no
  parity gap

#### Scenario: Glossary rows exist for the new affordances
- **WHEN** the change is reviewed
- **THEN** the glossary lists the two quick-create entries and the episode
  chip with their icons, labels and copy keys
