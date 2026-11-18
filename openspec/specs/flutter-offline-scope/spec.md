<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

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

### Requirement: Persisted Scope Is Evicted Only Against a Loaded Projection

A persisted reference to projection data (the active-season anchor in
`shell_state`, a per-season block scope) SHALL be evicted only when the
referenced projection has been **successfully read** and does not contain the
referenced id. A loading or failed read MUST NOT evict anything: an unloaded
projection is not evidence of absence, and dropping a live-but-unloaded
reference would destroy exactly the state the user needs once the fetch
succeeds.

The projection view SHALL therefore expose whether its rows are authoritative
(`SeasonsView.isLoaded`, `true` only for rows from a successful read,
defaulting to `false`), because the view deliberately always serves a usable
row list — cached rows while a fetch is in flight, retained rows after a
failure — so the row list alone cannot answer the question.

#### Scenario: A persisted anchor names a season a dev data reset deleted

- **WHEN** the persisted active-season anchor names a season and the seasons
  projection has loaded without it
- **THEN** the anchor is deleted from `shell_state`, so the next cold start
  starts clean instead of resolving `null` forever

#### Scenario: The seasons fetch is still in flight

- **WHEN** the persisted anchor names a season and the seasons fetch has not
  settled yet (or has failed and is serving retained rows)
- **THEN** the anchor is kept, and it is kept again after a later successful
  read that still contains the season

### Requirement: Persisted Scope Eviction Is Compare-and-Remove

A repair that decided from an earlier read SHALL remove a persisted value only
while the stored value still equals the one that was read. The comparison and
the delete SHALL be a single conditional statement (no read-modify-write
window), mirroring `ActiveBlockStore.removeScopeIfMatch` for the per-season
block scopes.

#### Scenario: A fresh pick lands between the read and the delete

- **WHEN** a repair reads a stale anchor and a concurrent user action writes a
  different, live anchor before the delete is issued
- **THEN** nothing is deleted and the fresh anchor resolves normally

### Requirement: Persisted Block Scopes of a Vanished Season Are Removed

The persisted per-season block scopes SHALL be pruned for every season a
loaded seasons projection no longer serves, using the per-entry conditional
removal (`removeScopeIfMatch`). Scopes of seasons the projection still serves
SHALL be left untouched — a stale *block* within a live season remains the
business of `blockScopeResolution`, which evicts it against that season's own
block fetch.

#### Scenario: A reset deletes the season a remembered block scope belongs to

- **WHEN** the loaded seasons projection lacks a season that still has a
  persisted block scope
- **THEN** that scope entry is removed and the scopes of live seasons are kept

### Requirement: Persisted Scope Repair Preserves Session Scoping

The session-scoped persistence key (`active_season_id@<sub>`) SHALL be derived
from a single provider used by both the read and the repair, so a repair can
only ever target the document the resolution read. Identity B MUST NOT delete
identity A's persisted reference.

#### Scenario: Identity B signs in on a device identity A used

- **WHEN** identity B's session resolves its (empty) anchor and identity A's
  anchor names a season the projection no longer serves
- **THEN** identity A's document is untouched and identity B evicts nothing

### Requirement: Persisted Scope Repair Is Best-Effort and Idempotent

A store failure during eviction SHALL degrade to "nothing repaired" (the next
cold start retries) and MUST NOT turn the repair into a rebuild loop: the
persisted providers are invalidated only after a settled successful write. A
converged state (nothing stale) SHALL perform no write at all.

#### Scenario: The shell boots with a clean persisted state

- **WHEN** the persisted anchor resolves to a live season and every persisted
  block scope belongs to a live season
- **THEN** the repair writes nothing

### Requirement: Persisted Episode Scope Is Evicted Only Against Loaded Projections

A persisted per-season episode reference (`ActiveEpisodeStore`) SHALL be evicted
only when the projection that can prove the reference dead has been
**successfully read** and does not contain it:

- the **seasons** projection for a scope whose season is gone, and
- that season's **episode** projection for the remembered episode.

A loading or failed read MUST NOT evict anything: an unloaded projection is not
evidence of absence, and dropping a live-but-unloaded reference would destroy
exactly the state the user needs once the fetch succeeds. The episode view
SHALL therefore expose whether its rows are authoritative (`EpisodesView
.isLoaded`, `true` only for rows from a successful read, defaulting to `false`),
because it deliberately always serves a usable row list — cached rows while a
fetch is in flight, retained rows after a failure.

#### Scenario: A reset deletes the season a remembered episode belongs to

- **WHEN** the persisted episode scope names a season and the seasons projection
  has loaded without that season
- **THEN** the scope entry is deleted from secure storage without any episode
  read

#### Scenario: The remembered episode no longer exists in a live season

- **WHEN** the persisted episode scope's season is served by the loaded seasons
  projection and that season's loaded, block-scoped episode projection does not
  contain the remembered episode
- **THEN** the scope entry is deleted and the in-memory episode scope is
  dropped, so no chip or quick-create entry points at the deleted episode

#### Scenario: The episode fetch is still in flight or has failed

- **WHEN** the persisted episode scope names a live season and the episode
  fetch has not settled (or failed and is serving retained rows)
- **THEN** the scope is kept, and it is kept again after a later successful read
  that still contains the episode

### Requirement: A Fresh Pick Is Not Evidence of Absence (Projector Lag)

A scope whose episode was PICKED by the live process within
`kEpisodeScopeSettleWindow` SHALL NOT be evicted, even when a loaded projection
does not contain it: a pick is written before the server-side projector carries
the new episode, so a successful read inside that window is a lagging read, not
a proof of absence (the AI-import "open imported episode" flow picks an episode
it has just created).

The pick time SHALL be recorded in memory only (never in the persisted
document), and a cold-start restore (`ActiveEpisode.set(isRestore: true)`) SHALL
NOT record one — otherwise every boot would renew the window and a dead scope
could never be evicted. After the window the same loaded absence is evidence and
the scope is evicted on the next evaluation.

#### Scenario: An AI import picks an episode the projector has not reached

- **WHEN** the user opens an episode the import has just created and the loaded
  episode projection does not carry it yet
- **THEN** the scope is kept (and its persisted document with it), and it is
  still kept on a later read, so the Script filter survives the lag

#### Scenario: The same episode is genuinely gone

- **WHEN** a scope older than the settle window is absent from a loaded
  projection (or the app cold-starts and the scope was restored, not picked)
- **THEN** the scope is evicted

### Requirement: Episode Scope Eviction Is Compare-and-Remove

A repair that decided from an earlier read SHALL remove a persisted episode
scope only while the stored entry still names the episode that was read
(`ActiveEpisodeStore.removeScopeIfMatch`). The in-memory sticky scope SHALL be
dropped on the same condition — the live `(seasonId, episodeId)` pair must still
match the evicted one. A fresh pick MUST survive, in the document and in memory.

#### Scenario: A fresh pick lands between the read and the delete

- **WHEN** a repair reads a stale episode scope and a concurrent user action
  writes a different, live episode of the same season before the removal is
  issued
- **THEN** nothing is removed, nothing is discarded from memory, and the fresh
  pick resolves normally

### Requirement: Episode Scope Repair Preserves Session and Season Scoping

The document SHALL stay a single identity-agnostic secure-storage key cleared by
`SessionReset`; the repair MUST only ever remove the entry of the season it read
and only runs while the shell is mounted, i.e. below `AuthGate`. It MUST NOT
introduce a per-identity key or rewrite any other season's entry.

#### Scenario: Identity B signs in on a device identity A used

- **WHEN** identity B's session resolves its (empty) episode document
- **THEN** identity A's document is untouched and identity B evicts nothing

#### Scenario: The app remembers episodes for several live seasons

- **WHEN** a remembered episode of the active season is dead and other live
  seasons also have remembered episodes
- **THEN** only the active season's entry is removed; the other seasons keep
  theirs and are repaired when they become active

### Requirement: Episode Scope Repair Is Owned by the Shell's Lifetime

The repair SHALL stop acting when the shell unmounts: the provider is
auto-dispose, so `AuthGate` dropping `AppShell` (sign-out) disposes it and an
in-flight eviction's `ref.mounted` fence prevents any later write or in-memory
discard. Every eviction SHALL be attributed to the scope whose removal
succeeded — one failed write MUST NOT discard a sibling scope's in-memory value
whose document is still stored.

#### Scenario: Sign-out lands between the decision and the write

- **WHEN** the shell is removed while an eviction is settling
- **THEN** nothing is written and no in-memory scope is discarded

### Requirement: Episode Scope Repair Is Best-Effort and Idempotent

A store failure during eviction SHALL degrade to "nothing repaired" (the next
cold start retries) and MUST NOT turn the repair into a rebuild loop: the
persisted provider is invalidated only after a settled successful write. A
converged state (nothing stale) SHALL perform no write at all.

#### Scenario: The shell boots with a clean persisted episode document

- **WHEN** every remembered episode belongs to a live season and the active
  season's episode is in its loaded projection
- **THEN** the repair writes nothing

