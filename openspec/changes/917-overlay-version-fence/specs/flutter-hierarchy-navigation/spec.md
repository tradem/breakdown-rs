<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-hierarchy-navigation

## ADDED Requirements

### Requirement: Update Overlays Reconcile on the Acknowledged Version

An overlay that carries an **update** to an already-projected row SHALL NOT
reconcile by projection id presence: the row is projected before the command, so
id presence is true before the fetch and carries no information about whether
the command reached the read model. Dropping on id presence discards the
optimistic value after a single fetch and leaves the screen on the stale
projected row — old value **and** old `version`, which then becomes the echo of
the next command (issue #917).

Every optimistic overlay SHALL therefore state, through the shared
`ReconciliationOverlay` contract, whether it is a **create** overlay (its id
appears in the projection only once the create is projected → id presence is the
completion signal) or an **update** overlay (it carries the aggregate version the
command's 2xx acknowledgement returned). The shared reconciliation runner SHALL
hand the freshly fetched `ProjectedRow`s (`id` + `version`) to the owning overlay
store, and the shared drop SHALL:

- keep an overlay whose id the projection does not carry yet;
- drop a **create** overlay once the projection carries its id;
- drop an **update** overlay only when the fetched row reaches its acknowledged
  version.

An update overlay SHALL be retained through the existing
`kMaxReconcileAttempts` budget and marked `stale` on exhaustion (never silently
discarded, D3). The version fence SHALL NOT introduce a new retry budget, a
wall-clock loop, or a client-side version guess: no per-aggregate overlay store
and no controller-side capture of the last projected versions may implement its
own comparison.

No implementation SHALL answer "create" for an overlay that edits a
pre-existing row; each implementation states the reason for its answer at the
declaration.

#### Scenario: The projector lags an update

- **GIVEN** a scene projected at version 1 and a details/beat update
  acknowledged at version 2
- **WHEN** the projection still serves the scene at version 1
- **THEN** the overlay (and its optimistic value) stays visible while the pass
  refetches within `kMaxReconcileAttempts`, waiting on the injected scheduler
  between attempts
- **AND** the overlay is retained marked `stale` when the budget is spent — it is
  never dropped, so the old value never flashes back

#### Scenario: The projection catches up inside the budget

- **WHEN** an attempt returns the row at (or after) the acknowledged version
- **THEN** the overlay is dropped and the projected row — new value **and** new
  `version` — is rendered

#### Scenario: A create overlay is unaffected

- **WHEN** a create overlay's id appears in the projection
- **THEN** the overlay is dropped on id presence, exactly as before: the id only
  appears once the create is projected

#### Scenario: A row the projection does not carry yet

- **WHEN** the fetched projection carries no row for the overlay's id
- **THEN** the overlay is kept (a create that has not reached the read model, or
  a row a later fetch still has to serve)
