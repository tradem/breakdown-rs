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

### Requirement: Repository Returns Result and Never Mutates Cache on Fetch Failure
The cache repository SHALL return `Result<T, ProblemError>` from its fetch
path and SHALL NOT mutate Drift on a fetch `Err` (no partial writes). On a
successful fetch it SHALL upsert-by-id inside a single transaction, and the
`@riverpod` controller SHALL convert that to an `AsyncValue` the screen reads
exclusively. No widget reads the API client or the cache directly.

#### Scenario: Fetch fails after a partial network response
- **WHEN** the generated client returns `Err(ProblemError)` for a seasons
  list fetch.
- **THEN** the repository returns `Err` without writing any row to Drift, and
  the controller surfaces `AsyncError` while preserving any previously
  emitted `AsyncData`.

### Requirement: TTL Expiry Marks Rows Stale Without Deleting Them
The cache SHALL mark rows stale when `clock.now() - updatedAt > ttl` (default
24h, tunable per table) and SHALL serve them with a `stale` indicator while
triggering a refetch. A failed refetch SHALL keep the stale rows and surface
the error.

#### Scenario: A cached row is older than the TTL
- **WHEN** the injected clock reports `now - updatedAt > ttl` for a cached
  season row.
- **THEN** the screen renders that row with a stale indicator and triggers a
  foreground refetch; a failed refetch keeps the row and shows an error
  banner rather than deleting it.

### Requirement: list() Uses Snapshot-Replace So Stale Rows Cannot Survive
For a top-level `list()` projection, a successful fetch SHALL upsert all
returned rows by id and DELETE any cached rows whose id is absent from the
returned set, in one transaction. No tombstones are used.

#### Scenario: A season is deleted server-side
- **WHEN** a `list()` fetch returns the seasons projection without a
  previously-cached season id.
- **THEN** that id's cached row is deleted in the same transaction, so it
  does not reappear from cache on the next cold read.

### Requirement: Stale Cache Retained Across Fetch Errors
When a fetch errors while valid cached rows exist, the provider SHALL emit an
error signal AND retain the cached rows with a stale marker, so the screen
can render them with an error/retry affordance. Task 3.3 (no silent discard)
and Task 4.1 (render cached rows) are jointly satisfiable.

#### Scenario: Fetch errors but cache has rows
- **WHEN** a refetch errors and the cache holds previously-fetched season
  rows.
- **THEN** the provider exposes `error != null` and `retainedStaleRows`
  non-empty; the widget shows the rows with a stale banner and a retry
  control, proving the two tasks are not in conflict.
