<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: SeasonsScreen as the Reference Screen Pattern
`SeasonsScreen` SHALL be a `ConsumerWidget` (no `StatefulWidget` /
`setState`) backed by a `@riverpod` `SeasonsController` returning
`AsyncValue<List<SeasonDto>>`, with optimistic create and bounded-retry
refetch on `POST /v1/seasons`. It is the reference pattern for all subsequent
screens.

#### Scenario: Creating a season optimistically
- **WHEN** the user submits the Create Season form.
- **THEN** the controller dispatches `POST /v1/seasons`, optimistically
  inserts the new row, and reconciles via a bounded-retry refetch of the
  seasons projection.

#### Scenario: A 409 conflict is returned
- **WHEN** `POST /v1/seasons` returns `409` with `code: seasons.conflict`.
- **THEN** the repository returns `Err(ProblemError(code:
  "seasons.conflict"))`, the controller surfaces it as `AsyncError`, the
  widget reverts the optimistic insert, and the error message is keyed on
  the stable `code` (never on `detail`).
