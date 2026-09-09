// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3 (opencode)

import 'package:drift/drift.dart';

/// Drift rows mirroring the shoot-day execution day-board projection
/// (`SceneShootView`) — not the event-store schema (AGENTS.md §8). Every
/// server field is preserved unchanged; the client-only [cachedAt] column
/// drives TTL (same discipline as [SeasonCacheRows]).
///
/// DTO-shape discipline: when `SceneShootView` gains or loses a field, the
/// matching column change AND its Drift migration ship in the same PR, so
/// the cache never silently drops a field.
///
/// Design notes (`flutter-shoot-day-execution` 1.2):
/// * Fetch scope is the shooting day: `list_scene_shoots` ignores the
///   `{scene_id}` path segment server-side and lists by day
///   (`ORDER BY COALESCE(actual_order, planned_order) ASC` — the Ist-aware
///   board sequence), so snapshots replace per `shootingDayId`.
/// * `notes` ride the shoot row as a JSON snapshot (no note-list route —
///   they refresh with the shoot row, like costume details/photos).
/// * `continuity_photo_ids` ride the row as a JSON id list (the ids resolve
///   to bytes via the photo pipeline, memory-cached only, never persisted).
/// * `snapshotIndex` persists the server order ordinal: SQLite guarantees no
///   row order without `ORDER BY`, so the snapshot position reproduces the
///   `COALESCE(actual_order, planned_order)` sequence exactly, including
///   order-key ties.
class SceneShootCacheRows extends Table {
  /// Mirrors `SceneShootView.id`.
  TextColumn get id => text()();

  /// Fetch scope: the shooting day (`list_by_shooting_day`, natively on
  /// the DTO as `shootingDayId`).
  TextColumn get shootingDayId => text()();

  /// Mirrors `SceneShootView.sceneId` (the pair's scene side).
  TextColumn get sceneId => text()();

  /// Mirrors `SceneShootView.plannedOrder` (Soll position key).
  TextColumn get plannedOrder => text()();

  /// Mirrors `SceneShootView.actualOrder` (Ist position key, nullable —
  /// `null` means execution has not rearranged this shoot).
  TextColumn get actualOrder => text().nullable()();

  /// Mirrors `SceneShootView.status` as the wire string
  /// (`Planned|Scheduled|InProgress|Shot|Skipped`; unknown variants
  /// strictly reject at parse time, never guessed).
  TextColumn get status => text()();

  /// Mirrors `SceneShootView.startDt` (nullable — `null` means not started).
  DateTimeColumn get startDt => dateTime().nullable()();

  /// Mirrors `SceneShootView.endDt` (nullable — `null` means not finished).
  DateTimeColumn get endDt => dateTime().nullable()();

  /// JSON snapshot of `SceneShootView.notes` (list of `SerializedNote`
  /// wire maps, serialized via the generated `breakdown_api` serializers).
  TextColumn get notesJson => text()();

  /// JSON snapshot of `SceneShootView.continuityPhotoIds` (plain id list).
  TextColumn get continuityPhotoIdsJson => text()();

  /// Mirrors `SceneShootView.updatedAt` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `SceneShootView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  /// Snapshot ordinal: position in the last `listShoots` response
  /// (server `ORDER BY COALESCE(actual_order, planned_order) ASC`).
  IntColumn get snapshotIndex => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
