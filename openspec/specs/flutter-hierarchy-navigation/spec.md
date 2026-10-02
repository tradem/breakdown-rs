# flutter-hierarchy-navigation Specification

## Purpose
TBD - created by archiving change flutter-hierarchy-navigation. Update Purpose after archive.
## Requirements

### Requirement: Hierarchy Navigation Spine
Season rows SHALL navigate to `BlocksScreen` (via `Navigator.push`, no new
routing package), block rows to `EpisodesScreen`, episode rows to
`ScenesScreen`. Each pushed screen SHALL receive the parent read DTO as
its navigation context; command payloads SHALL source every id
(`series_id`, `season_id`, `block_id`, `episode_id`) exclusively from that
DTO — never from an additional projection lookup. Back/Up SHALL return to
the parent list on both platforms.

#### Scenario: Navigating to a season's blocks
- **WHEN** an authenticated user taps a projected season row.
- **THEN** `BlocksScreen` pushes with that `SeasonView` as context and
  renders the season's `BlockView` rows (`GET /v1/blocks?season_id=…`).

#### Scenario: Navigating to a block's episodes
- **WHEN** the user taps a block row.
- **THEN** `EpisodesScreen` pushes with the `BlockView` as context and
  renders the block's `EpisodeView` rows via the server-side filter
  (`GET /v1/episodes?block_id=…`, backend issue #335); error copy is
  keyed on the stable problem `code` from the per-operation RFC 9457
  responses (backend issue #343).

#### Scenario: Back navigation
- **WHEN** the user invokes system back (Android) or mouse-back (macOS)
  on `EpisodesScreen`.
- **THEN** the navigator pops to `BlocksScreen` showing the same season
  context; no re-fetch storm is triggered by the pop itself.

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
