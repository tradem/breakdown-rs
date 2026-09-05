// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'hierarchy_cache.dart';
import 'season_cache.dart';

part 'cache_database.g.dart';

/// The read-projection cache database (Design Decision D1: cache is the single
/// source for screen state).
///
/// Tables mirror projection DTOs only. In production this is opened against a
/// file via [CacheDatabase.connect]; tests open an in-memory instance with the
/// default constructor.
@DriftDatabase(
  tables: [
    SeasonCacheRows,
    BlockCacheRows,
    EpisodeCacheRows,
    SceneCacheRows,
    CostumeCategoryCacheRows,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  /// Opens an in-memory database by default (used by tests). Production code
  /// passes a file-backed [QueryExecutor] via [CacheDatabase.connect].
  CacheDatabase([QueryExecutor? executor])
    : super(executor ?? NativeDatabase.memory());

  /// Opens the cache against an explicit [QueryExecutor] (file-backed in the
  /// app, in-memory in tests via [NativeDatabase.memory]).
  CacheDatabase.connect(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // Additive migrations for DTO-shape changes land here, in the same PR
      // as the projection DTO change (AGENTS.md §8 / Task 5.1). Each added
      // column uses `m.addColumn(...)` so the cache never silently drops a
      // field. No destructive (drop/rename) migrations are permitted; the
      // backend is authoritative for existence (D3: snapshot-replace).
      assert(from <= to, 'cache schema downgrade is unsupported');
      if (from < 2) {
        // `flutter-hierarchy-navigation` 2.1: hierarchy projection tables
        // (blocks, episodes, scenes, costume_categories mirroring the read
        // DTOs). Fresh tables for existing installs — no data to migrate.
        await m.createTable(blockCacheRows);
        await m.createTable(episodeCacheRows);
        await m.createTable(sceneCacheRows);
        await m.createTable(costumeCategoryCacheRows);
      }
    },
  );
}
