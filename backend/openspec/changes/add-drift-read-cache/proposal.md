<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Proposal: Add the Drift Read-Projection Cache

## Why
Foundation `flutter-offline-scope` (Q1→b) mandates an online-first app with
a Drift (type-safe SQLite) read-projection cache for fast boot and brief
offline read-only survival. This change implements the cache, the repository
pattern around it, and the TTL + on-write-invalidate policy.

## What changes
- Drift database under `data/cache/`; tables mirror read-projection DTOs.
- Repository pattern: fresh fetch → upsert-by-id into Drift → `AsyncValue`
  emit; cache is the single source for screen state.
- Cache invalidation: TTL + on-write-invalidate (successful command mutating
  a projection triggers a refetch).
- Cold-start offline render with stale indicator; write actions disabled.
- Drift migration test: shape change on a DTO → migration in same PR.

## Dependencies
- **Depends on:** `scaffold-flutter-project`, `wire-openapi-dart-client`
  (DTO shapes to mirror).
- **Unblocks:** `first-screen-seasons` (cache-backed SeasonsScreen).

## Non-goals
- No offline command queue (deferred per `flutter-offline-scope`).
- No sync/conflict resolution.
- No event-store schema mirror (cache mirrors projection DTOs only).

## Design Decisions (resolved during spec-hardening, issue #272)

The PR #269 review flagged open design questions on these stubs. They are
resolved here so implementation (Tasks) can proceed without re-litigating
them. Values marked *(tunable)* may be tuned at implementation; the
structural invariants are fixed and are encoded as requirements in
`specs/flutter-offline-scope/spec.md`.

### D1. Repository / provider boundary (single read source)

- The `Repository` (e.g. `SeasonsRepository`) owns the network + Drift write
  path and returns `Result<T, ProblemError>` (never `throw`).
- `fetchAndCache()`: calls the generated client `GET`; on `Ok` upserts-by-id
  into the Drift table inside **one transaction** and returns `Ok(unit)`; on
  `Err` returns `Err` **without mutating the cache** (no partial writes).
- `readCached()`: a pure Drift read (no network) returning the cached rows.
- The `@riverpod` controller **first** calls `readCached()` and emits the
  cached rows (seeding `prevRows` from this initial read), **then** triggers
  `fetchAndCache()`. On **each** successful read (initial cache read and every refetch) it re-reads and updates `prevRows = rows` before emitting `AsyncData(rows)`; on `Err`
  it emits `AsyncError` while preserving the **latest** emitted cached
  `AsyncData`/`prevRows` (see D4). This guarantees cached rows render on
  offline cold start even before the first fetch completes. Widgets
  `ref.watch` the provider only and never import the API client or call
  `readCached` directly.

### D2. TTL semantics (value: 24h *(tunable)*)

- Per-table TTL constant `kCacheTtl = const Duration(hours: 24)` *(tunable,
  per-table; fast-moving projections like scene_shoots may use a shorter
  value at implementation)*.
- **Clock**: an injected `Clock` (default `Clock()` = `DateTime.now()`),
  never a direct `DateTime.now()` call, so reconciliation tests use fake
  clocks (foundation deterministic-tests rule).
- Row model stores the server `updatedAt` (from `SeasonView.updated_at`,
  **preserved unchanged** by the client) AND a client-only `cachedAt` (set on
  upsert = cache write time). TTL is computed from `cachedAt`, never from the
  server `updatedAt`: `isExpired = clock.now().difference(cachedAt) > ttl`.
- Behaviors:
  - **Fresh** (`!isExpired`, non-empty): serve directly; still trigger a
    low-priority background refetch to absorb projector lag.
  - **Stale / Expired** (cache present but `isExpired`): serve cached rows
    with a `stale = true` marker; trigger a foreground-priority refetch; UI
    shows a "cached, refreshing" banner.
  - **Successful write**: upsert sets `updatedAt = clock.now()` -> row
    fresh.
  - **Failed refetch**: keep cached rows (stale marker on), surface
    `AsyncError` carrying the `ProblemError` + the retained rows (see D4);
    **no deletion** of cached rows on fetch failure.

### D3. Collection-fetch reconciliation (snapshot-replace)

- For top-level `list()` projections: **full-snapshot replace**. On a
  successful fetch, upsert all returned rows by id **and** delete any cached
  rows whose id is absent from the returned id set, all in one transaction.
  This guarantees no orphan/stale rows survive a complete snapshot
  (deletion handling = delete-missing-ids).
- **Tombstones**: not used. The backend is authoritative for existence; a
  row absent from a complete snapshot no longer exists -> deleted locally. A
  future paginated/delta endpoint defines its own delta-merge in its own
  change; this change pins snapshot-replace for `list()`.

### D4. Combined stale-data + fetch-error state

- The controller emits `AsyncError` on a fetch failure **but retains the
  last non-error list** in a private `prevRows` field. A `seasonsView`
  selector returns `{ rows: state.hasError ? prevRows : state.value,
  isStale: state.hasError || cachedRowsExpired, error: state.error }`, where
  `cachedRowsExpired` is the TTL result from D2 (derived from `cachedAt`, not
  a hardcoded `true`).
  Fresh successful rows are therefore never marked stale, while a failed
  refetch or expired cache still surfaces the stale banner.
- This satisfies both Task 3.3 (fetch error not silently discarded) and Task
  4.1 (cold-start/offline renders cached rows) simultaneously. A dedicated
  test (Task 4.3 / 2.3) asserts: cached rows exist + fetch errors ->
  provider emits error AND `retainedStaleRows` non-empty -> widget shows
  rows + stale banner + retry.
