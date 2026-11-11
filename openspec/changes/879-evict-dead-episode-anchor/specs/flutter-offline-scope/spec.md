<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-offline-scope

## ADDED Requirements

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

### Requirement: Episode Scope Repair Is Best-Effort and Idempotent

A store failure during eviction SHALL degrade to "nothing repaired" (the next
cold start retries) and MUST NOT turn the repair into a rebuild loop: the
persisted provider is invalidated only after a settled successful write. A
converged state (nothing stale) SHALL perform no write at all.

#### Scenario: The shell boots with a clean persisted episode document

- **WHEN** every remembered episode belongs to a live season and the active
  season's episode is in its loaded projection
- **THEN** the repair writes nothing
