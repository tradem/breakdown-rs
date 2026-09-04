<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-hierarchy-navigation Specification (delta)

## ADDED Requirements

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
