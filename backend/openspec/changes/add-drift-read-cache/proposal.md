<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

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
