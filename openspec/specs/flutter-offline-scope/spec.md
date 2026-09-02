# flutter-offline-scope Specification

## Purpose
TBD - created by archiving change add-flutter-app-foundation. Update Purpose after archive.
## Requirements
### Requirement: Online-First with Read-Projection Cache
The Flutter app SHALL be online-first: commands are always dispatched over
the network and never queued offline. Read projections SHALL be cached
locally in a Drift (type-safe SQLite) database so that the app boots fast,
shows "last seen" state on cold start, and survives brief connectivity
drops read-only. There is no offline write path in this change.

> Rationale: continuity-photo capture and costume assignment often happen at
> venues with flaky network, but full offline command queueing would force
> sync/conflict semantics and offline `series_id` resolution that the backend
> mandates come from event/command data (CQRS-boundary hard rule). A read
> cache covers ~80% of the pain without that scope expansion; offline
> *writes* are deferred to a later change.

#### Scenario: App cold-starts with no network
- **WHEN** the app launches offline (airplane mode).
- **THEN** the SeasonsScreen renders the last cached `SeasonDto` rows from
  Drift with a stale indicator, and write actions are disabled with a
  localized "online required" message.

#### Scenario: A read projection updates while online
- **WHEN** the device is online and a repository fetches a fresh projection.
- **THEN** the result is written into Drift (upsert by id) and the
  corresponding Riverpod provider emits the new state; the cache is the
  single source for the screen's `AsyncValue`.

### Requirement: No Offline Command Queue
No code path SHALL queue commands for later dispatch when offline. A failed
command returns `Err` to the provider; the widget surfaces a retry affordance.
This deliberately avoids sync/conflict resolution and offline
audit-metadata resolution, which would violate the backend's CQRS-boundary
hard rule if reconstructed client-side.

#### Scenario: User taps "Create Season" while offline
- **WHEN** the device is offline and the user submits the Create Season form.
- **THEN** the repository returns `Err(ProblemError(code:
  'network.unreachable'))`, the form stays populated for retry, and no
  command is persisted locally for later dispatch.

### Requirement: Drift as the Local Cache Store
The local cache SHALL be Drift (type-safe, codegen-friendly SQLite). Drift
tables mirror the read-projection DTOs (not the event-store schema). Cache
invalidation is TTL + on-write-invalidate (a successful command that
mutates a projection triggers a refetch of the affected read). The cache
is a performance/offline-tolerance layer only — it never holds state that
the server does not also hold.

#### Scenario: A projection DTO shape changes on the backend
- **WHEN** the generated Dart client gains/changes a field on `SeasonDto`.
- **THEN** the Drift table is migrated in the same PR (Drift migrations),
  so the cache never silently drops a field.

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
exclusively. No widget reads the API client or the cache directly. The
controller SHALL first emit the cached rows (seeding `prevRows`) and only
then trigger the network fetch, so a failing first fetch still renders cached
rows on offline cold start. The controller SHALL also refresh `prevRows` from
the latest successful read on every subsequent refetch, so a later fetch
error preserves the most recent good snapshot rather than the obsolete
initial one.

#### Scenario: Fetch fails after a partial network response
- **WHEN** the generated client returns `Err(ProblemError)` for a seasons
  list fetch.
- **THEN** the repository returns `Err` without writing any row to Drift, and
  the controller surfaces `AsyncError` while preserving the cached
  `AsyncData` it seeded from the initial Drift read.

### Requirement: TTL Expiry Marks Rows Stale Without Deleting Them

The cache SHALL mark rows stale when `clock.now() - cachedAt > ttl` (default
24h, tunable per table) and SHALL serve them with a `stale` indicator while
triggering a refetch. `cachedAt` is the client-only cache-write time (distinct
from the server `updatedAt` carried in the DTO, which is preserved unchanged);
TTL is computed from `cachedAt` only. A failed refetch SHALL keep the stale
rows and surface the error.

#### Scenario: A cached row is older than the TTL

- **WHEN** the injected clock reports `now - cachedAt > ttl` for a cached
  season row.
- **THEN** the screen renders that row with a stale indicator and triggers a
  foreground refetch; a failed refetch keeps the row and shows an error
  banner rather than deleting it.

### Requirement: list() Uses Snapshot-Replace So Stale Rows Cannot Survive

For a top-level `list()` projection, a successful fetch SHALL upsert all
returned rows by id and DELETE any cached rows whose id is absent from the
returned set, in one transaction. No tombstones are used. This
delete-missing-ids step runs ONLY on a complete, successful snapshot response;
a partial, paginated, or errored fetch MUST NOT delete any cached rows (an
unreturned id is safe to keep because the snapshot was not authoritative).

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

