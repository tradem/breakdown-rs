<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

## ADDED Requirements

### Requirement: Separate fundus browsing surface
The client SHALL provide a dedicated fundus browsing surface, reachable
from the Cast view (where the costume surface lives). It SHALL NOT be a
fifth facet chip of the OmniSearch surface, and the OmniSearch four-chip
set ("Szene" · "Rolle" · "Kostüm" · "Drehtag") SHALL remain unchanged.

#### Scenario: Fundus entry from the Cast view
- **WHEN** the user opens the Cast view with an active season and taps the
  fundus affordance
- **THEN** the fundus surface opens as its own screen with a visible
  "Fundus" title, without adding a chip to the OmniSearch surface

#### Scenario: OmniSearch is unchanged
- **WHEN** the user opens the OmniSearch surface
- **THEN** it still presents exactly the four facet chips and searches the
  active season only — no fundus chip and no cross-season rows appear there

### Requirement: Cross-season project scope
The fundus SHALL consider the costumes of the **active project** (the
project of the shell's active season), across all of that project's
seasons. Only costumes whose repertoire (`season_ids`) is non-empty and
intersects the project's seasons SHALL be included. Costumes of another
project SHALL NOT appear, and costumes without a repertoire binding SHALL
NOT appear.

#### Scenario: Costume carried into a second season is found once
- **WHEN** a costume is in the repertoire of season 1 and season 2 of the
  same project
- **THEN** it appears exactly once in the fundus, annotated with both
  season names

#### Scenario: Foreign-project costume excluded
- **WHEN** a costume belongs to a season of a different project
- **THEN** it does not appear in the fundus

#### Scenario: Non-repertoire costume excluded
- **WHEN** a costume is bound only to a character and has no repertoire
  binding
- **THEN** it does not appear in the fundus

### Requirement: Season facet chips and name prefilter
The fundus SHALL present a filter chip for each season of the active
project and a name prefilter. With no season chip selected the whole
fundus SHALL be shown; selecting one or more season chips SHALL narrow the
results to costumes whose repertoire intersects the selected seasons. The
text prefilter SHALL perform a case-insensitive, diacritics-insensitive
substring match over the pinned costume fields: notes (description) and
category name only. No network call SHALL be issued by the filtering
itself.

#### Scenario: Season chip narrows the fundus
- **WHEN** the user selects the "Staffel 2" chip
- **THEN** only costumes whose repertoire contains season 2 are shown

#### Scenario: Whole fundus by default
- **WHEN** no season chip is selected
- **THEN** costumes from every season of the active project are shown

#### Scenario: Diacritics-insensitive prefilter
- **WHEN** the user types "lederjacke"
- **THEN** a costume whose notes contain "Lederjacke" matches, using the
  same dictionary folding contract as the OmniSearch name prefilter

### Requirement: Repertoire-aware rows and deep links
Each result row SHALL show the costume's designation, its category, and
the names of its repertoire seasons. Tapping a row SHALL open the existing
costume detail screen, scoped to a repertoire season of the costume that
belongs to the active project (the active season when it is in the
repertoire, otherwise the first project-resident repertoire season). No
parallel route system SHALL be introduced.

#### Scenario: Row opens the costume detail
- **WHEN** the user taps a fundus row for a costume whose repertoire
  includes the active season
- **THEN** the costume detail screen opens for that costume scoped to the
  active season

#### Scenario: Cross-season costume opens via a repertoire season
- **WHEN** the user taps a fundus row for a costume that is not in the
  active season but is in another season of the project
- **THEN** the costume detail screen opens scoped to that other season and
  renders the costume

### Requirement: AI-import and non-repertoire data excluded
The fundus SHALL NOT surface AI-import draft/preview data (before apply),
and SHALL NOT surface non-costume entities. Only costume read-model rows of
the active project that carry a repertoire binding SHALL appear.

#### Scenario: AI-import draft is not searchable
- **WHEN** an AI-import job holds unapplied draft costumes and the user
  searches for a draft's text
- **THEN** no draft entity appears in the results

### Requirement: Cached-data honesty and states
The fundus SHALL reflect cache staleness honestly using the established
TTL/stale patterns and bounded-retry refetch (no new freshness semantics).
It SHALL distinguish an initial empty state, a zero-match state (echoing
the active season filter), a not-yet-loaded state, and an error state
(cache/storage failure) with localized copy. A storage failure SHALL
surface the visible error pattern — never a silent empty result presented
as ground truth.

#### Scenario: Storage failure surfaces an error
- **WHEN** the Drift DAO driving the fundus throws
- **THEN** the error state with localized problem copy is shown and the
  user can retry, matching the repo's `Result`/`ProblemError` conventions

#### Scenario: Stale cache indicator
- **WHEN** the cached fundus rows are older than the cache TTL
- **THEN** the established stale banner is shown above the results and
  pull-to-refresh runs a bounded refetch

#### Scenario: No active season
- **WHEN** no season is active
- **THEN** the fundus surface shows the localized no-season empty state
  and computes no results
