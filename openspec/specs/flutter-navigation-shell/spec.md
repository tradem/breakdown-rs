<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-navigation-shell Specification

## Purpose
TBD - created by archiving change 707-shell-tab-root-reset. Update Purpose after archive.
## Requirements
### Requirement: Tab Root Reset on Destination Selection

The shell SHALL reset the TARGET destination's nested navigator to its
root route when a destination is selected — both when SWITCHING to
another destination and when RE-TAPPING the already-active destination
(Material convention "re-tap = back to start"). The reset SHALL be
applied centrally in the shell's destination-selection handler so all
three morphologies (`NavigationBar`, `NavigationRail`,
`NavigationDrawer`) behave identically. Per-tab navigation position
memory across destination switches (former design D2) SHALL NOT exist.
When the target navigator is already at its root, the reset SHALL be a
no-op. The back contract (pop within the active destination's stack; at
a destination root no destination hopping; app-exit intent at the
initial Cast destination root) SHALL remain unchanged. The shell
controller SHALL distinguish a destination switch from a re-tap of the
already-active destination in its selection result and SHALL reject
out-of-range indices without changing state.

#### Scenario: Switching tabs shows the target's start screen

- **WHEN** the user has drilled into a destination's sub-pages (e.g.
  Settings opened from the account drawer, then a settings sub-page),
  switches to another destination, and returns.
- **THEN** the destination shows its start screen (root route), not the
  previously visited sub-page.

#### Scenario: Re-tap of the active destination pops to root

- **WHEN** the user taps the already-active destination while a
  sub-page is pushed on its nested navigator.
- **THEN** the navigator pops to the destination's root screen.

#### Scenario: Re-tap at the root is a no-op

- **WHEN** the user taps the already-active destination while its
  navigator is at the root route.
- **THEN** nothing changes (no error, no state transition).

#### Scenario: Reset applies in every morphology

- **WHEN** a destination is selected via the bottom `NavigationBar`
  (compact), the `NavigationRail` (medium) or the permanent
  `NavigationDrawer` (expanded).
- **THEN** the target destination's nested navigator is popped to its
  root in all three morphologies (one central handler).

#### Scenario: Back contract unchanged

- **WHEN** the user presses system back after the reset behavior is
  active.
- **THEN** back pops within the active destination's stack first, never
  hops destinations, and at the initial Cast destination root issues the
  app-exit intent (D3 unchanged).

#### Scenario: Out-of-range selection is still rejected

- **WHEN** the shell controller is asked to select a destination index
  below `0` or above `kScheduleTabIndex`.
- **THEN** the selected destination does not change and the selection
  result reports the rejection.

### Requirement: Episode Scope Implies Its Block Scope

The client SHALL treat the episode scope and the block scope as one
consistent pair: an episode belongs to exactly one block, so writing the
episode scope SHALL also establish the block scope of that episode's block
for the same season, and the block scope SHALL NEVER move to a different
block while an episode scope from the previous block stays active.

The cascade SHALL live in the single episode-scope write seam
(`ActiveEpisode.set`) so no call site — scope-pill picker, Script view scene
row, schedule tab, episodes screen rows, cold-start restore — can establish
an episode scope without its block scope. The block-scope value SHALL be
sourced from the acted-on episode read DTO (`blockId`), with the block number
carried from the acted-on block DTO when the caller holds it; when no number
is in hand the scope SHALL stay number-less and the block pill SHALL keep its
existing explicit "unknown block" narrative until the CACHE-ONLY number
backfill resolves it. A caller that holds the acted-on block number SHALL
write it even when the block scope already names the same block but is still
number-less (a label-less scope restored from an older document shape), so the
label does not wait for a cache row that may not exist; a block scope that
already carries a number SHALL NOT be rewritten. No additional network read
and no second projection lookup SHALL be introduced, and no block number SHALL
be invented.

The reverse direction SHALL hold as well: switching the block scope to a
different block SHALL drop an episode scope that does not belong to it (from
memory, and — when that episode scope belongs to the switched season — from
its persisted per-season document, so a cold start cannot resurrect the
stale pair). A persisted episode scope restored on cold start SHALL cascade
its block scope for the ACTIVE season only; a scope remembered for a
different season SHALL NOT seed a block scope. Clearing the block scope and
sign-out SHALL keep their existing semantics.

#### Scenario: Picking an episode with only a season selected sets the block scope

- **WHEN** only a season is active (no block scope) and the user picks an
  episode through the episode scope pill.
- **THEN** the episode scope is set from the picked episode, the block scope
  is set to that episode's block for the same season, and the block pill
  renders that block — with its number when the acted-on DTO carried one, or
  its honest "unknown block" narrative until the cache-only backfill resolves
  it.

#### Scenario: Opening a scene from the Script view sets both scopes

- **WHEN** the user taps a scene row in the Script view's season-wide
  composition.
- **THEN** both the episode scope and the block scope are set from the row's
  acted-on DTOs before the scene detail screen is pushed, and the block pill
  labels the block the row belongs to.

#### Scenario: A restored episode scope cascades its block scope

- **WHEN** the app cold-starts with a persisted episode scope for the active
  season and no in-memory block scope.
- **THEN** the restore sets the episode scope and cascades the block scope
  for that same season, so the shell never shows a highlighted episode pill
  next to an unset block pill.

#### Scenario: A foreign season's remembered episode never seeds a block scope

- **WHEN** a persisted episode scope exists for a season other than the active
  one.
- **THEN** no block scope is set from it; the existing season-switch handling
  (discard, or the active season's own remembered scope) decides the shell's
  scopes.

#### Scenario: Switching the block scope drops a foreign episode scope

- **WHEN** an episode scope belongs to block A and the user switches the block
  scope to block B.
- **THEN** the episode scope is cleared (memory and, for the same season, its
  persisted document), the shell never displays the pair "block B · episode of
  block A", and the episode pill falls back to its neutral arm for block B.

#### Scenario: A known block number completes a label-less matching scope

- **WHEN** the block scope already names the acted-on episode's block but
  carries no block number, and the call site holds the block number from the
  acted-on block DTO.
- **THEN** the number is written into the block scope (the pill labels the
  block immediately instead of waiting for the cache-only backfill), the
  episode scope is untouched, and a scope that already carries a number is
  never rewritten.

#### Scenario: No fabricated block number

- **WHEN** the cascade establishes a block scope without a known block number.
- **THEN** the block pill shows its explicit unknown-block narrative until the
  existing cache-only backfill resolves the number, and no network request is
  issued to obtain it.

