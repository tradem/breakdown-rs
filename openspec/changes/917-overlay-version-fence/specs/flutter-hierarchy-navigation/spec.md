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
`ReconciliationOverlay` contract, both facts the drop needs:

- whether it is a **create** overlay (its id appears in the projection only once
  the create is projected → id presence is the completion signal) or an
  **update** overlay (the row was projected before the command);
- the aggregate version the command's 2xx acknowledgement returned, which an
  **update** overlay SHALL supply (a create overlay MAY carry it for follow-up
  commands; its completion is still id presence).

The shared reconciliation runner SHALL hand the freshly fetched `ProjectedRow`s
(`id` + `version`) to the owning overlay store, and the shared drop SHALL:

- keep a **create** overlay whose id the projection does not carry yet (it has
  not projected);
- drop a **create** overlay once the projection carries its id;
- drop an **update** overlay when the projection no longer carries its row at
  all — the edited row was deleted or left the fetched scope, so no later fetch
  could ever reach the acknowledged version and keeping it would render a
  phantom row;
- otherwise keep an **update** overlay until the fetched row reaches its
  acknowledged version.

A follow-up command that replaces an overlay for an id that still carries a
**pending create** overlay SHALL keep the create identity: the row has not
projected yet, so an overlay re-flagged as an update would be completed by the
very next fetch that omits the id and the new row would vanish before its first
projection. The overlay's optimistic value and acknowledged version are still
replaced — only the completion signal stays id presence.

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

#### Scenario: A row the projection does not carry

- **WHEN** the fetched projection carries no row for a **create** overlay's id
- **THEN** the overlay is kept (the id only appears once the create is
  projected), even when the overlay echoes an acknowledged version

#### Scenario: An edit lands while the create has not projected

- **GIVEN** a create overlay whose row the projection does not carry yet
- **WHEN** a follow-up command (detail, notes, category, repertoire …) re-acks an
  overlay for that same id
- **THEN** the overlay keeps its create identity, so a fetch that still omits
  the id keeps it visible (the optimistic value is the follow-up's)
- **AND** it completes by id presence once the create reaches the projection

#### Scenario: The edited row is gone

- **WHEN** the fetched projection carries no row for an **update** overlay's id
  (the row was deleted or left the fetched scope)
- **THEN** the overlay is dropped on that fetch — no budget is spent on a
  version no later fetch can reach and no phantom row is rendered
- **AND** an empty successful fetch applies the same rule to every update
  overlay, while keeping every create overlay
- **AND** a failed fetch is never treated as absence: it never reaches the drop
  at all
