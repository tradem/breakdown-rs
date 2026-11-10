<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Proposal: Evict a dead persisted season anchor (issue #817, C4 of #809)

## Why

`#809` shipped C1 + C2 + C3a: a *configuration entry point* now renders its
state instead of hiding when its ambient scope is unresolved, so the
AI-configuration screen stayed reachable after a dev data reset (`#810` /
`#770`). That was the **tolerance** half. This is the **repair** half.

The client persists two pieces of ambient scope:

- the active-season anchor — `shell_state.active_season_id@<sub>`, read by
  `activeSeasonPersistedProvider` and resolved against the seasons projection
  by `activeSeasonResolutionProvider`;
- the per-season block scopes — one JSON document in secure storage
  (`ActiveBlockStore.key`), read by `activeBlockPersistedProvider`.

After a reset the projection serves none of the referenced seasons.
`activeSeasonResolution` already refuses to return such an id (`null`, "TTL
compliant by construction"), and `blockScopeResolution` evicts a stale scope
only per **resolved** season — which never happens for a season the projection
no longer serves. So the dead state was never removed: every scope-derived
consumer silently lost its anchor on every cold start until the user cleared
app data by hand. "A reset must be a routine operation" (`#810`) stayed
untrue for everything scope-derived.

## Decision

**D1 — Repair, do not merely tolerate, and only against a loaded projection.**
A new side-effect provider `activeScopeRepairProvider`
(`lib/features/shell/active_season_store.dart`) is watched once by `AppShell`.
It evicts the anchor once the seasons view has **loaded** and does not contain
it, plus every persisted per-season block scope whose season is gone. It
evicts nothing while the fetch is loading or has failed: a live-but-unloaded
season must never be dropped.

**D2 — `SeasonsView.isLoaded` is the only proof of absence.** The view
deliberately always exposes a usable row list — cached rows while the fetch is
in flight, retained rows after a failure (`flutter-offline-scope`) — so "has
rows" cannot distinguish *authoritative* from *retained*. Rather than reaching
past the view into the fetch controller (which would couple the repair to the
whole network chain and make `seasonsView` overrides insufficient), the view
gains one additive, fail-closed field: `isLoaded`, `true` only for rows that
came from a successful read. Default `false`, so an unconsidered construction
site can never authorize a deletion.

**D3 — Compare-and-remove, never an unconditional delete.** The anchor is
removed by a single conditional SQL delete (`ShellStateDao.deleteIfValue`,
`WHERE key = ? AND value = ?`), the shell-state twin of
`ActiveBlockStore.removeScopeIfMatch`. A repair that decided from an earlier
read therefore can never delete a fresh pick that landed in between — no
read-modify-write window exists. Block scopes use the existing
`removeScopeIfMatch(seasonId, blockId)`.

**D4 — Session scoping is preserved by construction.** The key space is
derived from one provider (`activeSeasonStorageKeyProvider`), used by both the
read and the repair, so an eviction can only ever target the document the
resolution actually read. Identity B never deletes identity A's anchor. (The
block-scope document is a single identity-agnostic key, cleared by
`SessionReset`; this change does not add a scope to it.)

**D5 — The resolution stays a pure resolver.** Eviction is not folded into
`activeSeasonResolutionProvider`: that provider is a keep-alive async provider
whose `.future` callers/tests await, and watching a further async provider
from it would supersede the awaited build (a rebuild makes the awaited future
never complete). The repair is its own provider with its own inputs; the
resolution's contract is untouched.

**D6 — Best-effort, idempotent, loop-free.** Every removal is fire-and-forget
and degrades to "nothing repaired" on a store failure; the persisted providers
are invalidated only after a *settled successful* write, so a broken store
cannot turn the repair into a rebuild loop. A converged state performs no
write at all.

## What Changes

- `lib/features/shell/active_season_store.dart`: new `activeScopeRepairProvider`
  (sync, keep-alive, side effect on watch), the `_evictGoneSeasons` helper, and
  the extracted `activeSeasonStorageKeyProvider` (one source for the key space).
- `lib/data/cache/shell_state_cache_dao.dart`: new `deleteIfValue` (conditional
  delete, `shell.state_delete_failed` on failure).
- `lib/data/cache/seasons_view.dart`: additive `isLoaded` (default `false`).
- `lib/data/cache/seasons_cache_providers.dart`: the controller marks a
  successful snapshot `isLoaded: true`; the retained-row branches state
  `isLoaded: false` explicitly.
- `lib/features/shell/app_shell.dart`: watches `activeScopeRepairProvider`
  (the shell is what runs the repair, as it already restores the
  active-episode scope).
- Tests: `test/unit/shell/active_season_repair_test.dart` (10 cases: eviction,
  no-eviction while loading/failed, compare-and-remove race, session scoping,
  idempotence, and the two store-failure branches proving no rebuild loop),
  `test/features/shell/active_season_repair_test.dart` (3 widget cases through
  the shell's own watch), plus `deleteIfValue` coverage in
  `test/unit/shell/shell_state_cache_test.dart`.

### Deliberately out of scope

- **The persisted active-episode scope** (`activeEpisodeStore`) has the same
  shape of staleness (a season-scoped episode anchor). Repairing it needs its
  own eviction predicate (episode ids are not resolved through a single
  projection view); follow-up issue.
- **A backend-pushed invalidation.** The client repairs from the projection it
  already fetches; no new wire signal is introduced.
