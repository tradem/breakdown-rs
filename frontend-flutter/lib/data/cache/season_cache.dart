// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:drift/drift.dart';

/// Drift row mirroring the `SeasonView` read-projection DTO (not the event-store
/// schema — AGENTS.md §8). Every server field is preserved unchanged; the
/// client-only [cachedAt] column drives TTL (Design Decision D2).
///
/// DTO-shape discipline (Task 5.2 / AGENTS.md §8): when `SeasonView` gains or
/// loses a field, the matching column change AND its Drift migration ship in
/// the same PR, so the cache never silently drops a field.
class SeasonCacheRows extends Table {
  /// Mirrors `SeasonView.id`.
  TextColumn get id => text()();

  /// Mirrors `SeasonView.number`.
  IntColumn get number => integer()();

  /// Mirrors `SeasonView.series_id` (opaque `SeriesId`).
  TextColumn get seriesId => text()();

  /// Mirrors `SeasonView.title` (nullable).
  TextColumn get title => text().nullable()();

  /// Mirrors `SeasonView.updated_at` — server timestamp, preserved unchanged.
  DateTimeColumn get updatedAt => dateTime()();

  /// Mirrors `SeasonView.version` (optimistic-locking round-trips).
  IntColumn get version => integer()();

  /// Client-only cache-write time. Distinct from [updatedAt]; TTL is computed
  /// from this column only (D2).
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
