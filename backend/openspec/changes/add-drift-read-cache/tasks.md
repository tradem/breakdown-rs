<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Drift database
- [ ] 1.1 Drift database under `data/cache/`; tables mirror read-projection
       DTOs (not the event-store schema)
- [ ] 1.2 `drift_dev` codegen wired into `build_runner`

## 2. Repository cache pattern
- [ ] 2.1 Fresh fetch → upsert-by-id into Drift → `AsyncValue` emit
- [ ] 2.2 Cache is the single source for screen state (no direct API reads
       in widgets)
- [ ] 2.3 Unit tests: cache upsert + read round-trips; Err branch on fetch
       failure
- [ ] 2.4 Snapshot-replace reconciliation test: a `list()` fetch returning N
       rows SHALL delete cached rows whose id is absent from the set, in the
       same transaction (asserts D3 delete-missing-ids)

## 3. Invalidation
- [ ] 3.1 TTL invalidation per table
- [ ] 3.2 On-write-invalidate: successful command mutating a projection
       triggers a refetch of the affected read
- [ ] 3.3 No silent discarded fetch errors (surface as `AsyncError`)

## 4. Offline behavior
- [ ] 4.1 Cold-start offline render of last cached rows with stale indicator
- [ ] 4.2 Write actions disabled with localized "online required" message
- [ ] 4.3 Widget test for the stale-indicator + disabled-FAB path
- [ ] 4.4 Combined stale+error test: fetch errors with cached rows present ->
       provider emits error AND `retainedStaleRows` non-empty -> widget shows
       rows + stale banner + retry (jointly satisfies Task 3.3 ∧ Task 4.1)

## 5. Migration discipline
- [ ] 5.1 Drift migration test: DTO shape change → migration in same PR
- [ ] 5.2 Document the cache-never-drops-a-field rule in `AGENTS.md` §8

## Spec-hardening (issue #272) — design resolved

The PR #269 review flagged open design questions for this change. They are
resolved in `proposal.md` (Design Decisions D1–D4) and encoded as
requirements in `specs/flutter-offline-scope/spec.md`. Implementation Tasks
1–5 remain open; the design gap is closed.
- [x] Repository/provider boundary defined (D1: `fetchAndCache` → upsert in
      one txn → `readCached` → `Result`; controller → `AsyncValue`; widgets
      read provider only)
- [x] TTL semantics + fresh/stale/expired/successful-write/failed-refetch
      scenarios defined (D2: 24h tunable, injected `Clock`, stale marker,
      keep-on-failure)
- [x] Collection-fetch reconciliation defined (D3: snapshot-replace,
      delete-missing-ids, no tombstones) — asserted by Task 2.4
- [x] Combined stale-data + fetch-error state + test defined (D4: retain
      `prevRows`, `seasonsView` selector with derived `isStale`, asserts 3.3 ∧
      4.1) — asserted by Task 4.4
