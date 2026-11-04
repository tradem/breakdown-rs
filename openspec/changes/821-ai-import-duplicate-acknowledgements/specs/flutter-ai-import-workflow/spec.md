<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-ai-import-workflow

## ADDED Requirements

### Requirement: One acknowledgement row per blocking decision

The apply card SHALL render exactly ONE acknowledge row per
`(scene_index, field)` pair, never one per preview entry. A preview may report
several blocking `field_ambiguity` entries for the same pair; they are one
question with several notes, so the client SHALL collapse them into one
decision (the first entry supplies the row's note, and the preview screen keeps
listing every entry with its own note).

The apply request SHALL carry exactly one `uncertainty_acknowledgement` per
acknowledged pair, and SHALL never carry the same pair twice. Apply SHALL stay
disabled until every pair is acknowledged, and SHALL be enabled once the last
open pair is acknowledged — acknowledging one pair resolves all of its entries.

#### Scenario: Duplicate blockers render one row

- **WHEN** the preview carries three blocking `field_ambiguity` entries for
  `(0, category)` and one for `(1, episode)`
- **THEN** the apply card renders two acknowledge rows
- **AND** toggling the first row acknowledges all three entries of `(0, category)`

#### Scenario: The wire list carries no duplicate pair

- **WHEN** the reviewer acknowledges every row and dispatches the apply
- **THEN** `uncertainty_acknowledgements` carries one entry per pair (two
  entries for the preview above), never a repeat
- **AND** the apply reaches the worker instead of failing at the API edge

#### Scenario: A single-entry preview is unchanged

- **WHEN** the preview carries exactly one blocking entry per pair
- **THEN** the panel renders one row per entry and the request stays
  byte-identical to the pre-#821 client
