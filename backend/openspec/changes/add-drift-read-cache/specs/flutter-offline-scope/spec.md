<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Drift Read-Cache as Single Source for Screen State
The Drift cache SHALL be the single source a screen reads from. A fresh
projection fetch upserts-by-id into Drift and emits via the provider; no
widget reads the API client directly.

#### Scenario: App cold-starts offline
- **WHEN** the app launches in airplane mode.
- **THEN** the screen renders the last cached rows from Drift with a stale
  indicator and disables write actions with a localized "online required"
  message.

### Requirement: Drift Migration on DTO Shape Change
A projection DTO shape change SHALL ship with a Drift migration in the same
PR, so the cache never silently drops a field.

#### Scenario: A field is added to SeasonDto
- **WHEN** the generated `SeasonDto` gains a field.
- **THEN** the Drift table is migrated in the same PR and the migration
  test asserts the field round-trips.
