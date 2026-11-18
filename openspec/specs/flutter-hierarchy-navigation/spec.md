<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-hierarchy-navigation Specification

## Purpose
TBD - created by archiving change flutter-hierarchy-navigation. Update Purpose after archive.
## Requirements
### Requirement: Hierarchy Navigation Spine

Season rows SHALL navigate to `BlocksScreen` (via `Navigator.push`, no new
routing package), block rows to `EpisodesScreen`, episode rows to
`ScenesScreen`. Each pushed screen SHALL receive the **full ancestor chain
as an immutable `PlanningLocation`** in `RouteSettings.arguments` — a typed
sealed ladder (`season → block → episode → scene`) in which each step
requires the previous one, so a non-contiguous chain (e.g. an episode
without its block) is not representable. Command payloads SHALL source
every id (`series_id`, `season_id`, `block_id`, `episode_id`) exclusively
from the read DTOs held by that location — never from an additional
projection lookup. Back/Up SHALL return to the parent list on both
platforms.

The shell SHALL render a visible **context strip** above the tab content in
all window-size morphologies, derived from the topmost route's location of
the active tab's navigator (pop and tab switches update it without extra
state), showing every level as icon AND visible text; when the width is
insufficient it collapses to the last segments while its merged semantics
node always announces the full path. Season-direct screens (costumes,
characters, costume categories, character detail) take the **season level
only** — they are not part of the block/episode chain and SHALL NOT pretend
to be. The shell SHALL also render a separate **scope chip** whenever an
active-block scope is set, showing the scoped block's label (degrading to
an explicit "unknown" narrative when the label cannot be resolved — never a
silent filter), indicating when the scope's season differs from the
navigated season, and opening the block picker on tap so the scope is
changeable.

#### Scenario: Navigating to a season's blocks
- **WHEN** an authenticated user taps a projected season row.
- **THEN** `BlocksScreen` pushes with that `SeasonView` as context and a
  `PlanningLocation.season` argument, and renders the season's `BlockView`
  rows (`GET /v1/blocks?season_id=…`); the strip shows the season.

#### Scenario: Navigating to a block's episodes
- **WHEN** the user taps a block row.
- **THEN** `EpisodesScreen` pushes with the `BlockView` as context and a
  `PlanningLocation.block` argument (season included) and renders the
  block's `EpisodeView` rows via the server-side filter
  (`GET /v1/episodes?block_id=…`, backend issue #335); error copy is
  keyed on the stable problem `code` from the per-operation RFC 9457
  responses (backend issue #343); the strip shows season and block.

#### Scenario: Navigating to an episode's scenes
- **WHEN** the user taps an episode row.
- **THEN** `ScenesScreen` pushes with a `PlanningLocation.episode`
  argument carrying season, block and episode DTOs; the strip shows all
  three — the season title is visible at every deeper level.

#### Scenario: Back navigation
- **WHEN** the user invokes system back (Android) or mouse-back (macOS)
  on `EpisodesScreen`.
- **THEN** the navigator pops to `BlocksScreen` showing the same season
  context; no re-fetch storm is triggered by the pop itself; the context
  strip updates to the season level **in the same frame** (the location is
  carried by the route, so no stale level can survive the pop).

#### Scenario: Invisible scope made visible
- **WHEN** an active-block scope is set (picked, restored from persistence,
  or single-block resolved) and the user navigates.
- **THEN** the scope chip is visible with the scoped block's label, so a
  silently filtered list is explainable; when the scope's season differs
  from the navigated season the chip says so instead of presenting the
  foreign block as if it applied; tapping the chip opens the block picker.

#### Scenario: Season-direct screens take the season level only
- **WHEN** the user enters `CostumesScreen`, `CharactersScreen`,
  `CharacterDetailScreen` or `CostumeCategoriesScreen` from season level.
- **THEN** the pushed route carries a `PlanningLocation.season` argument
  and the strip shows the season only — never a fabricated block/episode
  context.

### Requirement: Screen Pattern Parity With the Reference
Each hierarchy screen SHALL follow the seasons reference pattern:
`ConsumerWidget` container rendering `asyncValue.when` for
loading/error/data; pure presentation widgets under `widgets/` with no
Riverpod imports receiving plain data and callbacks; a `@riverpod`
family controller whose state carries projected `AsyncValue` rows,
cached rows, staleness, optimistic overlays and a dismissible command
error; a Result-typed repository wrapping the generated client plus a
Drift cache table (TTL staleness, snapshot-replace lists, no cache
mutation on fetch failure).

#### Scenario: Loading and error states
- **WHEN** a screen's projection is loading or the fetch fails (`Err`).
- **THEN** the container shows a progress affordance (`CircularProgressIndicator`
  or skeleton) or the error state with retry; the previous cached rows
  remain visible on failure (stale-indicated), and the error is keyed on
  the problem `code`.

#### Scenario: Empty state
- **WHEN** a screen's merged row list is empty and no fetch is failing.
- **THEN** a plain-language empty state renders with the create call to
  action when the session gate allows it.

#### Scenario: 404 while viewing a deleted parent's children
- **WHEN** a pushed list screen's fetch returns a `*.not-found` problem.
- **THEN** the screen renders a 404 narrative and a back affordance; it
  does not render fabricated or stale rows as if current.

### Requirement: Optimistic-Above-2xx Create With Shared Reconciliation
Create commands (block, episode, scene) SHALL insert the optimistic
overlay only after the 2xx acknowledgement, as controller state never
written to Drift, and SHALL reconcile via a bounded-retry refetch that
drops the overlay when the projection carries its id. The overlay/
backoff/reconciliation machinery SHALL be shared with the seasons screen
(a single `lib/domain/reconciliation/` implementation, seasons golden-
parity preserved); overlays MUST be retained with a stale indicator and
pull-to-refresh option after retry exhaustion, never silently discarded.

#### Scenario: Creating a block
- **WHEN** the user submits the Create Block form (ids from the parent
  `SeasonView`).
- **THEN** `POST /v1/blocks` dispatches after the session AUTHZ-GATE;
  on 2xx an `acknowledged` overlay keyed by the returned id renders
  immediately and the bounded-retry reconciliation replaces it with the
  projected row.

#### Scenario: Conflict or validation failure
- **WHEN** the create returns 409/422 before any 2xx.
- **THEN** no overlay exists, no Drift write occurs, and localized copy
  keyed on the problem `code` renders.

#### Scenario: Projector-lag exhaustion
- **WHEN** the bounded reconciliation retries are exhausted.
- **THEN** the overlay stays visible marked stale with the
  pull-to-refresh suggestion; Drift contains no unprojected row.

### Requirement: Season Membership Read and Display
A family provider SHALL fetch `GET /v1/seasons/{id}/membership` and
strictly parse `SeasonMembershipDto`; an unknown capability string SHALL
reject the DTO as `Err`. The current season context SHALL display the
caller's role state (capabilities chip, or an explicit "no role in this
season" chip). Phase 1 uses the membership read for display only; gated
capability actions beyond it are future-phase concerns.

#### Scenario: Membership with costume role
- **WHEN** the backend returns `has_active_costume_role_in_season: true`
  with the known capability set.
- **THEN** the chip renders the capability state; no re-fetch occurs on
  child navigation (TTL-scoped read).

#### Scenario: Unknown capability string
- **WHEN** a future backend adds a capability the client does not know.
- **THEN** the strict parser rejects the DTO with a stable problem code
  (never a guessed policy), surfaced as the standard error state.

### Requirement: Adaptive, Accessible Presentation on Both Platforms
Every hierarchy screen SHALL render correctly in light AND dark themes
(golden-tested for both) and on compact Android phones (touch targets
≥48 dp, pull-to-refresh, FAB) and macOS desktop widths (hover/focus
affordances, keyboard traversal, Escape-closable dialogs, no
`NavigationRail`). Overlay and error surfaces SHALL use Material progress
affordances; the UI thread SHALL never be blocked by projection work.

#### Scenario: Dark-mode goldens across platforms
- **WHEN** golden tests run for each screen in
  {light, dark} × {android, macos} variants.
- **THEN** all variants match their committed goldens.

#### Scenario: Create form never janks
- **WHEN** a create command dispatches and reconciliation runs.
- **THEN** dispatch returns after the acknowledgement; reconciliation
  runs off the widget tree with a visible overlay spinner — no frozen
  frames from awaited projector lag.

### Requirement: Labelled Reports Entry On The Shooting-Days Screen

The shooting-days screen (`ShootingDaysScreen`) SHALL carry a reports entry
as a **labelled** control — visible label `Berichte` with an icon
reinforcing only, per the glossary's visible-label norm — that pushes the
episode's report index. The entry SHALL follow the adaptive pattern #549
established for the day board's reports entry: a `TextButton.icon` that
collapses into a **labelled** overflow-menu item at narrow widths, never
into a bare icon, with the width decision taken from a
`LayoutBuilder` breakpoint rather than a platform check. The Gherkin
contract key `reportsIndexOpen` SHALL sit on the tap target in **both**
branches, so the contract step resolves at either width.

The shooting-day tiles SHALL keep their existing action set: the index is
the single new affordance, and no tap target is added to a row that
already carries rename, reschedule, unschedule, archive and move actions.

The design decision D8 — reports are day-scoped and anchored in the day
board — is widened by this entry to: reports are day-scoped, anchored in
the day board, and **indexed per episode**. The per-day report surface
itself is unchanged.

#### Scenario: The entry is labelled and pushes the index

- **WHEN** the shooting-days screen renders at a width that fits the label
- **THEN** a control with the visible label `Berichte` and the key
  `reportsIndexOpen` renders, and tapping it pushes the report index for
  that episode

#### Scenario: The entry stays labelled at narrow widths

- **WHEN** the same screen renders at a width too narrow for the label
- **THEN** the entry collapses into an overflow-menu item that is labelled
  `Berichte` and still carries the key `reportsIndexOpen` on its tap target
  — it never degrades to an unlabelled icon

#### Scenario: Day rows do not gain a tap target

- **WHEN** the shooting-days screen renders its day rows
- **THEN** each row offers only its existing rename, reschedule,
  unschedule, archive and move actions — no report navigation target is
  added to the row

### Requirement: Season Id In The Shooting-Days Navigation Context

`ShootingDaysScreen` SHALL receive the season id as a **required named
navigation-context parameter**, threaded down by `EpisodesScreen` from the
parent `BlockView.season_id` — the same field `ScenesScreen` already
receives on the adjacent push. The shooting-days screen SHALL NOT resolve
the season id through a second projection read (for example a
`GET /v1/blocks/{id}` or an episode-side season lookup) to fill in
navigation context, and SHALL NOT read the shell's active season, because
the spine supports browsing a season that is not the active one. Command
payloads pushed from the shooting-days screen SHALL continue to source
every id exclusively from the parent DTO the user is acting on.

#### Scenario: The season id comes from the parent DTO

- **WHEN** the user taps an episode's shooting-days entry
- **THEN** `ShootingDaysScreen` is pushed with that episode's `EpisodeView`
  and the parent `BlockView.season_id`, and no additional request is issued
  to resolve the season

#### Scenario: A browsed, non-active season keeps its own context

- **WHEN** the user browses a season that is not the shell's active season
  and opens an episode's shooting-days screen there
- **THEN** the screen's season context is the browsed season's id, not the
  active season's

### Requirement: Overlay-less Commands Reconcile on the Acknowledged Version

A command that inserts **no** optimistic overlay (a single-intent update such as
a shooting-day `reschedule` / `rename` / `reorder` / `unschedule`, a character
contact/measurements/category correction, a costume-category rename, a
continuity-photo link/unlink, or an archive) SHALL NOT reconcile by projection
id presence: the row is already projected, so id presence is true before the
fetch and carries no information about whether the command reached the read
model.

Such a command SHALL record the acted-on row and the aggregate version its 2xx
body returned, and the shared reconciliation runner SHALL compare that
acknowledged version with the version of the freshly fetched row:

- a fetched version at or after the acknowledged one ends the pass;
- a row the projection no longer carries (archive/delete) ends the pass;
- a fetched version *older* than the acknowledged one SHALL be retried within
  the SAME `kMaxReconcileAttempts` budget, driven by the injectable
  `ReconciliationScheduler` — never a new budget, never a wall-clock loop.

On exhaustion the older row the last fetch wrote SHALL be retained as-is (no
silent discard, no fabricated row) and the acknowledgement SHALL be consumed so
a single lag cannot slow every later refresh. The command's own semantics MUST
stay unchanged: no optimistic overlay, no extra command dispatch, and the
version echo still comes from the acted-on DTO.

The refetch seam SHALL carry the version (`ProjectedRow`: id + aggregate
version) so every wiring site states which version its projection rows carry.
A wiring site whose command set cannot lag MUST say so at the wiring
(create-only command set → the overlay branch reconciles; commands whose
acknowledged version belongs to another aggregate or to two aggregates → no
fetched row of this projection could match it).

#### Scenario: The projector lags a reschedule

- **GIVEN** a shooting day projected at version 1 with date A
- **WHEN** `reschedule` is acknowledged with version 2 and the projection still
  serves the day at version 1
- **THEN** the pass refetches up to `kMaxReconcileAttempts` times, waiting on
  the injected scheduler between attempts
- **AND** the stale row (date A, version 1) stays in place — no overlay, no
  fabricated row, no dropped row
- **AND** no new retry budget and no wall-clock delay are introduced

#### Scenario: The projection catches up inside the budget

- **WHEN** an attempt returns the row at the acknowledged version (or higher)
- **THEN** the pass ends immediately, without spending the remaining attempts
- **AND** the projected row shows the new value AND its new `version`

#### Scenario: A row the command removed from the projection

- **WHEN** an archive is acknowledged and the projection no longer carries the
  row
- **THEN** the pass ends after that fetch (absence is caught up, not lag)

#### Scenario: A failed fetch is not freshness

- **WHEN** an attempt fails (`Err`, no rows)
- **THEN** the attempt is spent and the next one asks again — a failure never
  ends the pass as if the projection were current

#### Scenario: A second command is acknowledged mid-pass

- **WHEN** a later overlay-less acknowledgement arrives while a pass is in
  flight
- **THEN** a dedicated follow-up pass runs for it
- **AND** the finishing pass does not clear the newer acknowledgement

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

