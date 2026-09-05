// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:drift/drift.dart';

/// Drift rows mirroring the hierarchy read-projection DTOs (not the
/// event-store schema — AGENTS.md §8). Every server field is preserved
/// unchanged; the client-only [cachedAt] columns drive TTL (same discipline
/// as [SeasonCacheRows]).
///
/// DTO-shape discipline: when a `*View` gains or loses a field, the matching
/// column change AND its Drift migration ship in the same PR, so the cache
/// never silently drops a field.

// --- Blocks (mirrors `BlockView`) -------------------------------------------

class BlockCacheRows extends Table {
  /// Mirrors `BlockView.id`.
  TextColumn get id => text()();

  /// Mirrors `BlockView.number`.
  IntColumn get number => integer()();

  /// Mirrors `BlockView.seasonId` (fetch scope: `GET /v1/blocks?season_id=`).
  TextColumn get seasonId => text()();

  /// Mirrors `BlockView.seriesId` (opaque `SeriesId`, carried into
  /// `CreateEpisodeRequest` from the read DTO the user acts on).
  TextColumn get seriesId => text()();

  /// Mirrors `BlockView.startDate` (wire string, preserved unchanged).
  TextColumn get startDate => text()();

  /// Mirrors `BlockView.endDate` (wire string, preserved unchanged).
  TextColumn get endDate => text()();

  /// Mirrors `BlockView.updatedAt` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `BlockView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- Episodes (mirrors `EpisodeView`) ----------------------------------------

class EpisodeCacheRows extends Table {
  /// Mirrors `EpisodeView.id`.
  TextColumn get id => text()();

  /// Mirrors `EpisodeView.blockId` (fetch scope + `groupByBlock` key).
  TextColumn get blockId => text()();

  /// Mirrors `EpisodeView.name` (nullable).
  TextColumn get name => text().nullable()();

  /// Mirrors `EpisodeView.number`.
  IntColumn get number => integer()();

  /// Mirrors `EpisodeView.seriesId` (opaque `SeriesId`).
  TextColumn get seriesId => text()();

  /// Mirrors `EpisodeView.updatedAt` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `EpisodeView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- Scenes (mirrors `SceneView`) --------------------------------------------

class SceneCacheRows extends Table {
  /// Mirrors `SceneView.id`.
  TextColumn get id => text()();

  /// Mirrors `SceneView.episodeId` (fetch scope:
  /// `GET /v1/scenes?episode_id=`).
  TextColumn get episodeId => text()();

  /// Mirrors `SceneView.assignedCharacters` (JSON-encoded id list;
  /// display count-only in Phase 1b, no mutation).
  TextColumn get assignedCharacters => text()();

  /// Mirrors `SceneView.isScheduleSet`.
  BoolColumn get isScheduleSet => boolean()();

  /// Mirrors `SceneView.location` (nullable, read-only detail data).
  TextColumn get location => text().nullable()();

  /// Mirrors `SceneView.mood` (nullable, read-only detail data).
  TextColumn get mood => text().nullable()();

  /// Mirrors `SceneView.sceneNumber` (nullable).
  IntColumn get sceneNumber => integer().nullable()();

  /// Mirrors `SceneView.scriptDay` (nullable, read-only detail data).
  TextColumn get scriptDay => text().nullable()();

  /// Mirrors `SceneView.shootingDayIds` (JSON-encoded id list;
  /// display count-only in Phase 1b).
  TextColumn get shootingDayIds => text()();

  /// Mirrors `SceneView.summary` (nullable, read-only detail data).
  TextColumn get summary => text().nullable()();

  /// Mirrors `SceneView.updatedAt` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `SceneView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- Costume categories (mirrors `CostumeCategoryView`) ----------------------

class CostumeCategoryCacheRows extends Table {
  /// Mirrors `CostumeCategoryView.id`.
  TextColumn get id => text()();

  /// Mirrors `CostumeCategoryView.seasonId` (fetch scope:
  /// `GET /v1/seasons/{season_id}/costume-categories`).
  TextColumn get seasonId => text()();

  /// Mirrors `CostumeCategoryView.name`.
  TextColumn get name => text()();

  /// Mirrors `CostumeCategoryView.orderKey` (server `ORDER BY order_key
  /// ASC`; the client never re-sorts beyond presenting this key).
  TextColumn get orderKey => text()();

  /// Mirrors `CostumeCategoryView.archived` (hidden behind the archived
  /// toggle, never silently unlisted).
  BoolColumn get archived => boolean()();

  /// Mirrors `CostumeCategoryView.updatedAt` — server timestamp, preserved
  /// unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `CostumeCategoryView.version` (rename echoes this row's
  /// version for optimistic locking).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
