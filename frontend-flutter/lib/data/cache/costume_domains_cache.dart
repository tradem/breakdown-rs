// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:drift/drift.dart';

/// Drift rows mirroring the Phase-2 costume-domain read-projection DTOs (not
/// the event-store schema — AGENTS.md §8). Every server field is preserved
/// unchanged; the client-only [cachedAt] columns drive TTL (same discipline
/// as [SeasonCacheRows]).
///
/// DTO-shape discipline: when a `*View` gains or loses a field, the matching
/// column change AND its Drift migration ship in the same PR, so the cache
/// never silently drops a field.
///
/// Design notes (flutter-costume-domains D-tasks):
/// * `CostumeView` carries NO `season_id` on the wire — `seasonId` is the
///   fetch-scope column (from `GET /v1/costumes?season_id=`), like
///   `BlockCacheRows.seasonId`. `details`/`photos` ride the costume row as
///   JSON snapshots (there is no detail/photo list route).
/// * `CharacterView` carries `season_id` natively; measurements (7 required
///   strings) are flattened, contact is flattened to nullable columns.
/// * `ShootingDayView` carries `episode_id` natively; `source` (externally-
///   tagged `Manual | AiExtracted`) is stored as the wire JSON string;
///   `date` is stored as ISO-8601 `yyyy-MM-dd` text (nullable); `wrapped_at`
///   as DateTime (nullable).

// --- Costumes (mirrors `CostumeView` + fetch-scope `seasonId`) ---------------

class CostumeCacheRows extends Table {
  /// Mirrors `CostumeView.id`.
  TextColumn get id => text()();

  /// Fetch scope: `GET /v1/costumes?season_id=` (NOT on the wire DTO).
  TextColumn get seasonId => text()();

  /// Mirrors `CostumeView.characterId` (nullable assignment).
  TextColumn get characterId => text().nullable()();

  /// Mirrors `CostumeView.notes`.
  TextColumn get notes => text()();

  /// JSON snapshot of `CostumeView.details` (list of `CostumeDetailView`
  /// wire maps, serialized via the generated `breakdown_api` serializers).
  TextColumn get detailsJson => text()();

  /// JSON snapshot of `CostumeView.photos` (list of `CostumePhotoView`
  /// wire maps, each with nested `variants`). Never cached independently —
  /// rides the costume row (no photo-list route).
  TextColumn get photosJson => text()();

  /// Mirrors `CostumeView.updatedAt` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `CostumeView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- Characters (mirrors `CharacterView`, flattened) --------------------------

class CharacterCacheRows extends Table {
  /// Mirrors `CharacterView.id`.
  TextColumn get id => text()();

  /// Mirrors `CharacterView.seasonId` (fetch scope).
  TextColumn get seasonId => text()();

  /// Mirrors `CharacterView.name`.
  TextColumn get name => text()();

  /// Mirrors `CharacterView.category` (`main_cast|guest|extra` wire string;
  /// unknown variants strictly reject at parse time, never guessed).
  TextColumn get category => text()();

  /// Flattened `CharacterMeasurements` (all seven required strings).
  TextColumn get height => text()();
  TextColumn get weight => text()();
  TextColumn get chest => text()();
  TextColumn get waist => text()();
  TextColumn get hips => text()();
  TextColumn get shoeSize => text()();
  TextColumn get hatSize => text()();

  /// Flattened `ContactInfo` (both nullable).
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();

  /// Mirrors `CharacterView.updatedAt` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `CharacterView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- Shooting days (mirrors `ShootingDayView`) --------------------------------

class ShootingDayCacheRows extends Table {
  /// Mirrors `ShootingDayView.id`.
  TextColumn get id => text()();

  /// Mirrors `ShootingDayView.episodeId` (fetch scope).
  TextColumn get episodeId => text()();

  /// Mirrors `ShootingDayView.orderKey` (server `ORDER BY order_key ASC`;
  /// the client never re-sorts).
  TextColumn get orderKey => text()();

  /// Mirrors `ShootingDayView.source` as wire JSON (`"Manual"` or
  /// `{"AiExtracted":{...}}`). Stored verbatim so future variants survive.
  TextColumn get sourceJson => text()();

  /// Mirrors `ShootingDayView.label` (nullable).
  TextColumn get label => text().nullable()();

  /// Mirrors `ShootingDayView.date` as ISO-8601 `yyyy-MM-dd` text (nullable;
  /// `null` = unscheduled. Distinct from absent — see update semantics).
  TextColumn get date => text().nullable()();

  /// Mirrors `ShootingDayView.archived`.
  BoolColumn get archived => boolean()();

  /// Mirrors `ShootingDayView.wrappedAt` (nullable — `None` means open).
  DateTimeColumn get wrappedAt => dateTime().nullable()();

  /// Mirrors `ShootingDayView.updatedAt` — server timestamp, preserved.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `ShootingDayView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. TTL is computed from this column only.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
