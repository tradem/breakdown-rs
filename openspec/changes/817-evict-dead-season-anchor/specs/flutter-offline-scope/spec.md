<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-offline-scope

## ADDED Requirements

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
