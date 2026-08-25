<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Online-First with Read-Projection Cache
The Flutter app SHALL be online-first: commands are always dispatched over
the network and never queued offline. Read projections SHALL be cached
locally in a Drift (type-safe SQLite) database so that the app boots fast,
shows "last seen" state on cold start, and survives brief connectivity
drops read-only. There is no offline write path in this change.

> Rationale: continuity-photo capture and costume assignment often happen at
> venues with flaky network, but full offline command queueing would force
> sync/conflict semantics and offline `series_id` resolution that the backend
> mandates come from event/command data (CQRS-boundary hard rule). A read
> cache covers ~80% of the pain without that scope expansion; offline
> *writes* are deferred to a later change.

#### Scenario: App cold-starts with no network
- **WHEN** the app launches offline (airplane mode).
- **THEN** the SeasonsScreen renders the last cached `SeasonDto` rows from
  Drift with a stale indicator, and write actions are disabled with a
  localized "online required" message.

#### Scenario: A read projection updates while online
- **WHEN** the device is online and a repository fetches a fresh projection.
- **THEN** the result is written into Drift (upsert by id) and the
  corresponding Riverpod provider emits the new state; the cache is the
  single source for the screen's `AsyncValue`.

### Requirement: No Offline Command Queue
No code path SHALL queue commands for later dispatch when offline. A failed
command returns `Err` to the provider; the widget surfaces a retry affordance.
This deliberately avoids sync/conflict resolution and offline
audit-metadata resolution, which would violate the backend's CQRS-boundary
hard rule if reconstructed client-side.

#### Scenario: User taps "Create Season" while offline
- **WHEN** the device is offline and the user submits the Create Season form.
- **THEN** the repository returns `Err(ProblemError(code:
  'network.unreachable'))`, the form stays populated for retry, and no
  command is persisted locally for later dispatch.

### Requirement: Drift as the Local Cache Store
The local cache SHALL be Drift (type-safe, codegen-friendly SQLite). Drift
tables mirror the read-projection DTOs (not the event-store schema). Cache
invalidation is TTL + on-write-invalidate (a successful command that
mutates a projection triggers a refetch of the affected read). The cache
is a performance/offline-tolerance layer only — it never holds state that
the server does not also hold.

#### Scenario: A projection DTO shape changes on the backend
- **WHEN** the generated Dart client gains/changes a field on `SeasonDto`.
- **THEN** the Drift table is migrated in the same PR (Drift migrations),
  so the cache never silently drops a field.
