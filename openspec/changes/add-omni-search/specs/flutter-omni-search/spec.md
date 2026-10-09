<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

## ADDED Requirements

### Requirement: Top-bar search entry point
The app shell SHALL surface a persistent search affordance in the top bar (placement defined by GitHub issue #613) that opens the OmniSearch surface from anywhere inside the shell. The affordance SHALL NOT be a navigation destination tab of the bottom bar.

#### Scenario: Opening the search surface
- **WHEN** the user taps the top-bar search affordance
- **THEN** the OmniSearch surface opens with the facet chips visible and an active text input focus, without leaving the shell's navigation stack

#### Scenario: Search is data-only
- **WHEN** the OmniSearch surface is open
- **THEN** it contains no action affordances (no create commands, no navigation shortcuts) — data search only

### Requirement: Facet-driven result scoping
The search SHALL scope results by exactly four facet types, presented as toggleable chips in the shipped German copy "Szene", "Rolle", "Kostüm" and "Drehtag". All four facets SHALL be active by default, and results SHALL always be grouped by facet type — no mixed single list.

#### Scenario: All facets by default
- **WHEN** the user opens the search surface with no facet deselected
- **THEN** matching scenes, characters (roles), costumes and shooting days are all returned, grouped under localized type headers in the canonical order: scenes → roles → costumes → shooting days

#### Scenario: Restricting to one facet
- **WHEN** the user deselects the "Szene", "Rolle" and "Drehtag" chips, keeping only "Kostüm"
- **THEN** only costume results are returned and the other groups are absent (not merely empty)

### Requirement: Active-season scope
The search SHALL consider only read-model data of the currently active season (the shell's season scoping, consumed from `flutter-hierarchy-navigation` — never a second projection lookup). Cross-season data SHALL NOT appear in results.

#### Scenario: Switching season changes the result universe
- **WHEN** the active season changes while the search surface reflects a new query
- **THEN** results are computed over the newly active season's data only, and any previous results from the other season are gone

#### Scenario: No active season
- **WHEN** no season is active (first-run state)
- **THEN** the search surface shows the localized empty-state copy and no results are computed

### Requirement: Name prefilter over cached season data
For the active facet(s) the search SHALL filter the locally cached read DTOs (Drift cache) of the active season by a case-insensitive, diacritics-insensitive substring match over each type's naming fields: scenes (scene number prefix and synopsis), characters (name), costumes (description), shooting days (label or date). No network call SHALL be issued by the search itself.

#### Scenario: Character search
- **WHEN** the user types "zoe" with the "Rolle" facet active
- **THEN** every character of the active season whose name contains "zoe" case-insensitively is returned

#### Scenario: German diacritics
- **WHEN** the user types "wohnung"
- **THEN** a scene whose synopsis contains "Wohnung" matches, and a synopsis containing "Woehnung" does not match unless it literally contains "wohnung" (dictionary folding, not fuzzy matching)

#### Scenario: Offline behavior
- **WHEN** the device is offline and the user performs a search with a populated cache
- **THEN** the search works entirely from the cache and is not degraded by missing connectivity

### Requirement: Grouped results with deep links
Each result row SHALL link into the corresponding destination screen of the redesigned navigation (GitHub issue #610): a scene result opens the scene detail screen, a character result opens the character detail screen, a costume result opens the costume detail/assignment context, a shooting-day result opens the shooting day screen. Deep-link targets SHALL be the same routes those navigation views use — no parallel route system is introduced.

#### Scenario: Scene result deep link
- **WHEN** the user taps a scene result row
- **THEN** the scene detail screen for that scene opens (shell back stack semantics as from the Script view)

#### Scenario: Deep links survive navigation redesign
- **WHEN** the #610 navigation redesign changes tab structure or route keys
- **THEN** the search deep links resolve through the same destination screens, and this change's deep-link tests fail if a target screen is renamed or removed

### Requirement: AI-import drafts excluded
The search SHALL NOT surface AI-import draft/preview data (before apply). Only entities that are part of the domain read models — imported and applied, or manually created — SHALL appear in results. This is a PO-confirmed non-goal with stable wording in this capability's contract.

#### Scenario: Draft scene is not searchable
- **WHEN** an AI-import job holds unapplied draft scenes and the user searches for a draft's synopsis text
- **THEN** no draft entity appears in the results; only applied domain entities match

### Requirement: Cached-data honesty
Because search operates on the client cache, the search surface SHALL reflect cache staleness honestly: it SHALL use the established projector-lag reconciliation patterns (stale indicators on cached-derived views, bounded-retry refetch on user action) and SHALL NOT present the cache as server truth beyond what the existing read surfaces do. No new freshness semantics are introduced.

#### Scenario: Stale cache indicator
- **WHEN** the cache rows backing a result group are flagged stale per the existing cache-generation semantics
- **THEN** the results remain visible with the established stale indicator (same treatment as the orginated read screens), not hidden and not silently presented as fresh

### Requirement: Empty, zero-match, and error states
The search surface SHALL distinguishes three states with localized copy (de/en): initial empty state (before typing), zero-match state (no results after a query), and error state (cache/storage failure reading the search inputs). A storage error SHALL surface the established visible-error pattern — never a silent empty result presented as ground truth.

#### Scenario: Zero matches
- **WHEN** the user's query matches no entity in any active facet
- **THEN** the localized zero-match copy is shown with the knowingly searched facets echoed

#### Scenario: Storage failure
- **WHEN** the Drift DAO driving a facet throws
- **THEN** the error state with localized problem copy is shown and the user can retry, matching the repo's `Result`/`ProblemError` conventions
