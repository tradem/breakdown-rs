<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Flutter: fault-injection coverage for costume-domain cache failures (issue #369)

## Why

The `flutter-costume-domains` data layer maps Drift faults to `Result` values
(never throws, AGENTS.md §5): `cache.write_failed` / `cache.read_failed` /
`cache.clear_failed` in `CostumeRepository`, `CharacterRepository` and
`ShootingDayRepository`. These defensive branches are currently uncovered: a
closed in-memory database does not reliably produce DAO faults in tests
(verified during the original implementation — reads resolve instead of
throwing), so the `on Object` mappings had no deterministic trigger. The
pooled coverage gate (80, CI `coverage` job) passes without them, but an
unmatched `Err` variant is a visible coverage hole per the test-pyramid spec
(flutter-test-pyramid: every `Result`-returning repo path asserts Ok AND Err).

## Decisions

- **Seam: scriptable DAO fake wrapping a real DAO** (not a throwing
  `QueryExecutor` wrapper). The three costume-domain cache DAOs are concrete
  classes with small implicit interfaces; a `implements`-fake that delegates
  to a real in-memory DAO and throws on demand gives a per-operation script
  (write / read / clear), which an executor-level seam cannot distinguish
  without parsing SQL (`applySnapshot*` and `clear*` both emit DELETE
  statements, and snapshot writes run inside transactions).
- **Test-only seam:** zero production-code changes — the `try`/`on Object`
  mapping stays as-is (issue non-goal). The fakes live in the test file.
- **Cache-untouched-on-failure asserted against the real DAO:** the fake
  wraps a genuine `CostumeCacheDao` / `CharacterCacheDao` /
  `ShootingDayCacheDao` over an in-memory Drift database, so "cache untouched"
  reads persisted state, not the fake's memory.
- **Determinism:** fixed `Clock.fixed` clock, scriptable Dio interceptor, no
  wall-clock budgets, no real network, no Flutter imports (Tier-1 unit).

## Plan

1. `test/unit/costume_domain_cache_faults_test.dart` (new): private
   `_InjectedFault` exception + `_FaultPhase` enum (none / write / read /
   clear) + three delegating DAO fakes (`_FaultCostumeCacheDao`,
   `_FaultCharacterCacheDao`, `_FaultShootingDayCacheDao`), reusing the wire
   fixtures from `costume_domain_repositories_test.dart`.
2. Per repository cover Ok AND Err:
   - Costume: `listBySeason` write-fault, `readCached` read-fault,
     `clearCache` clear-fault, `getAndCache` write-fault (upsert).
   - Character: `listBySeason` write-fault, `readCached` read-fault,
     `clearCache` clear-fault.
   - ShootingDay: `listByEpisode` write-fault, `readCached` read-fault,
     `clearCache` clear-fault.
   - Each Err asserts the documented `Left` code
     (`cache.write_failed` / `cache.read_failed` / `cache.clear_failed`) and
     that the cache is untouched (prior rows survive / target row absent).
3. No production or generated-file changes; no `backend/openapi.yaml` change
   (OpenAPI drift check is a no-op for this change).

## Non-goals

- No mutation-testing gate (Decision D5 — none exists for Dart; the four
  compositional substitutes stand).
- No offline command queue / no additional repository behavior.

## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| (none) | — | Test-only change: one new `test/unit/` file; no production, generated, or dependency change |

## References

- `openspec/changes/flutter-costume-domains/` (tasks 1.6, 8.3/8.4).
- `frontend-flutter/lib/data/costume_repository.dart`,
  `character_repository.dart`, `shooting_day_repository.dart` (fault
  mapping); `frontend-flutter/test/unit/costume_domain_repositories_test.dart`
  (existing Ok/Err pattern extended).
