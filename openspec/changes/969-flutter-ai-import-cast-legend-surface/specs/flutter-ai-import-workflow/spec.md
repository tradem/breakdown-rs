<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta — issue #969

## ADDED Requirements

### Requirement: The schedule preview states its cast legend

A schedule preview (`AiPreviewPayloadOneOf1`) SHALL render the payload's
`castLegend` as a COLLAPSED disclosure directly under the payload header. The
collapsed title SHALL state the entry count (ICU plural, one key per locale).
Each expanded entry SHALL show the numeric code in tabular figures, the
character name, and a role-modifier badge when `modifier != none`. Entries SHALL
be ordered numerically by code (then alphabetically for non-numeric codes).

An ABSENT or EMPTY legend map SHALL render NOTHING: no card, no placeholder and
no "no legend" sentence.

#### Scenario: A schedule preview carries a legend
- **WHEN** the preview's `ShootingSchedule.castLegend` holds four entries
- **THEN** one collapsed legend card renders under the payload header and states four entries
- **AND** no entry is visible until the reviewer expands it
- **AND** expanding it lists `2`, `33`, `150`, `1040` in that numeric order

#### Scenario: A preview predates the legend field
- **WHEN** the stored preview carries no `castLegend` (or an empty one)
- **THEN** the preview renders exactly as it did before this change, with no legend card at all

### Requirement: A role modifier is a localized badge, never a colour alone

Every `ScheduleRoleModifier` other than `none` SHALL render as one pill whose
label is the production vocabulary the extraction prompt uses (`Dummy`,
`Nur Stimme`, `(OT)`), coloured from an M3 container role
(`secondaryContainer`, `tertiaryContainer`, `primaryContainer`). The SAME badge
SHALL be used in the legend and on the rows' cast pills.

Each badge SHALL carry a `Semantics` label that states the modifier AND its
meaning; `none`, an absent modifier and an unknown future value SHALL render
NOTHING.

#### Scenario: A screen reader announces a modifier
- **WHEN** a cast member carries `ScheduleRoleModifier.voiceOnly`
- **THEN** the visible pill reads `Voice only` in the English catalog
- **AND** its accessibility label is "<modifier> · role modifier stated by the schedule"

### Requirement: Resolved cast and pick-up/insert suffixes are visible per row

A schedule row (`ShootingScheduleRow`) SHALL render one pill per RESOLVED
`castRefs` entry (character name + modifier badge) and, when `shotSuffix` is
present, an outlined suffix chip carrying the verbatim suffix with an
accessible label naming what it means. Both SHALL render on pre-merge schedule
rows and on the merged review's per-row lines (verbatim `rowRef` + suffix chip +
cast pills).

A row whose codes did not resolve SHALL render NO chip: the server drops unknown
codes by design, so an "unknown cast" warning would imply an error state that
does not exist. A row that carries neither a resolved code nor a suffix SHALL
render nothing.

#### Scenario: Two shoot rows on one scene
- **WHEN** a merged scene carries `300.37` and `300.37N`
- **THEN** one line per row renders, each with its own resolved cast
- **AND** only `300.37N` carries the suffix chip
- **AND** apply still treats both rows identically

### Requirement: The #968 EU vision providers are first-class AI-config options

The AI-config provider picker, the reachability probe, the per-provider health
card and the credential entry SHALL remain catalog/wire-key driven, so
`scaleway`, `ovhcloud` and `nebius` are selectable and probed under their wire
keys with no per-provider special case.

The curated-model dropdown SHALL NOT gain a client-side vision-capability
signal while the wire (`ModelInfo`) carries none.

#### Scenario: A configuration on an EU vision provider renders its health
- **WHEN** the stored configuration's provider is `ovhcloud` and the catalog serves that key
- **THEN** the extraction health card renders and asks the route about `ovhcloud`
