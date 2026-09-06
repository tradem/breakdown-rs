<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->

# Proposal: Derive hierarchy `isStale` from cache TTL expiry (issue #366)

## Summary

Hierarchy view selectors (`seasonsView`, `blocksView`, `episodesView`,
`scenesView`, `costumeCategoriesView`) currently mark `isStale: true`
whenever retained rows are served during loading/error (`prev.isNotEmpty`),
even when the cache has not expired. A fresh cached projection therefore
shows a stale banner while a normal refetch is in flight.

## Change

- Add one TTL-based staleness seam per scope, backed by the existing
  repository `isCacheStale` (DAO `is*Expired`, `cachedAt`-based, 24h default):
  `seasonsCacheStale`, `blocksCacheStale(seasonId)`,
  `episodesCacheStale(blockId)`, `scenesCacheStale(episodeId)`,
  `costumeCategoriesCacheStale(seasonId)`. Each watches its repository +
  injectable `clockProvider`; failures resolve to `false` (fail-closed).
- View selectors keep `AsyncError => isStale: prev.isNotEmpty` (failed
  refetch serving retained rows) and change only the loading branch to
  `isStale: prev.isNotEmpty && (ttlStale ?? false)`.
- `AsyncData` (fresh fetch) stays `isStale: false`.

## Non-goals

- No change to `isCacheStale`/DAO/TTL semantics, no new endpoints, no
  offline command queue.
- No hand-edits to `*.g.dart` / `vendor/breakdown_api/` (regenerate via
  `build_runner`).

## Validation

- `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`.
- New provider tests: loading + fresh cache => no banner; loading +
  expired cache => banner; error + retained rows => banner (unchanged).
