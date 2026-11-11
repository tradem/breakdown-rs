<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Proposal: Evict a persisted episode scope that resolves to no row (issue #879, C5 of #809)

## Why

`#817` repaired the persisted **active-season** anchor and the per-season
**block** scopes: once the seasons projection has loaded without the referenced
season, the client evicts them itself, so a dev data reset (`#810` / `#770`)
stopped degrading scope-derived UI until the operator cleared app data by hand.

The third piece of persisted ambient scope — the per-season **episode**
reference (`ActiveEpisodeStore`, `breakdown.active_episode_scopes`) — kept the
same shape of staleness and was never evicted. `AppShell._restoreEpisodeScope`
restores it on cold start; after a reset the referenced episode (and often its
season) no longer exists, so the restore resolves to nothing and the entry stays
in secure storage forever. Runbook §13 therefore still told operators to drop
the persisted scope by hand — exactly the degradation `#817` removed for the
season anchor.

## Decision

**D1 — A sibling repair provider, not an extension of the season repair.**
`activeEpisodeScopeRepairProvider`
(`lib/features/shell/active_episode_scope_repair.dart`) is a second sync,
keep-alive side-effect provider, watched once by `AppShell` next to
`activeScopeRepairProvider`. The two documents have different proofs of absence
(the seasons view vs. a block-scoped episode projection) and different eviction
targets; keeping one owner per persisted document leaves `#817`'s
behaviour — and its thirteen tests — untouched.

**D2 — Two proofs of absence, one of them free.** Nothing about the episode
scope is evicted from "has rows":

- a scope whose **season** the loaded seasons projection no longer serves is
  removed outright. This is the dev-data-reset case and needs no episode read
  at all;
- the **active** season's remembered episode is probed against its own
  projection (`episodesListFetchProvider`, block-scoped, the same seam the
  episode chip picker uses). An episode belongs to exactly one block and the
  document names that block, so `(blockId, seasonId)` absence is absence.
  Only the active season is probed: every other live season is repaired when it
  becomes active, so a cold start never fans out into one episode fetch per
  remembered season.

**D3 — `EpisodesView.isLoaded` is the episode's proof of absence.** The
episode view has the same contract as `SeasonsView` — it deliberately always
serves a usable row list (cached rows while the fetch is in flight, retained
rows after a failure) — so "has rows" cannot distinguish *authoritative* from
*retained*. The view gains one additive, fail-closed field (`isLoaded`, `true`
only for a success snapshot, default `false`), mirroring `#817`'s D2. No
eviction happens while either fetch is loading or has failed.

**D4 — Compare-and-remove, never an unconditional delete.** New
`ActiveEpisodeStore.removeScopeIfMatch(seasonId, episodeId)` — the exact twin of
`ActiveBlockStore.removeScopeIfMatch` — removes a season entry only while it
still names the episode that was read, so a fresh pick (or its in-flight
write) can never be deleted, whatever the scheduling order.

**D5 — The in-memory scope is dropped with the document.** Evicting only the
document would leave the dead episode rendered in the shell's episode chip:
`_restoreEpisodeScope` deliberately keeps an in-memory scope whose season still
matches. After a settled successful write the repair discards the sticky scope
when it still names the evicted `(seasonId, episodeId)` pair — a
compare-and-remove on the live value, so a fresh pick is never discarded.

**D6 — Session and season scoping are preserved.** The document stays a single
identity-agnostic key cleared by `SessionReset`; the repair only ever runs when
the shell is mounted, i.e. below `AuthGate`, and only ever removes the *named*
season's entry. No new key space is introduced.

**D7 — Best-effort, idempotent, loop-free.** Each removal is fire-and-forget and
degrades to "nothing repaired" on a store failure; the persisted provider is
invalidated only after a settled successful write, so a broken store cannot turn
the repair into a rebuild loop, and a converged state performs no write at all.

## What Changes

- `lib/features/shell/active_episode_scope_repair.dart` (new): the repair
  provider, the dead-set computation and the two eviction steps.
- `lib/features/episodes/episodes_controller.dart`: additive
  `EpisodesView.isLoaded` (default `false`); the controller marks a successful
  snapshot `true`, the retained-row branches state `false` explicitly.
- `lib/auth/active_episode_store.dart`: new `removeScopeIfMatch`.
- `lib/features/shell/app_shell.dart`: watches the new provider.
- `backend/docs/operations/runbooks.md` §13: the manual scope clear is gone; the
  one residual case (a live season whose block the backend refuses with an error
  rather than an empty list) is stated honestly.
- Tests: `test/unit/shell/active_episode_scope_repair_test.dart` (11 cases
  driving the real providers) and
  `test/features/shell/active_episode_scope_repair_test.dart` (4 widget cases
  through a probe that watches exactly what `AppShell` watches), plus
  `removeScopeIfMatch` coverage in `test/auth/active_episode_store_test.dart`,
  and a `failWrites` knob on the shared secure-storage fake.

### Deliberately out of scope

- **A cold-start fetch budget change.** The active season's episode projection
  is read once per cold start *when* a persisted episode scope exists for it —
  the same list the episode chip picker and the episodes screen need anyway.
  Not fetching would mean never proving absence.
- **A failed read as evidence.** A backend that answers the episode list with
  403/404 (a block the caller may no longer see) keeps the entry until a later
  successful read; probabilistic eviction was rejected in `#817` for the same
  reason.
- **A backend-pushed invalidation.** The client repairs from projections it
  already fetches; no new wire signal.
