<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

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

## 3. Invalidation
- [ ] 3.1 TTL invalidation per table
- [ ] 3.2 On-write-invalidate: successful command mutating a projection
       triggers a refetch of the affected read
- [ ] 3.3 No silent discarded fetch errors (surface as `AsyncError`)

## 4. Offline behavior
- [ ] 4.1 Cold-start offline render of last cached rows with stale indicator
- [ ] 4.2 Write actions disabled with localized "online required" message
- [ ] 4.3 Widget test for the stale-indicator + disabled-FAB path

## 5. Migration discipline
- [ ] 5.1 Drift migration test: DTO shape change → migration in same PR
- [ ] 5.2 Document the cache-never-drops-a-field rule in `AGENTS.md` §8
