// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'ai_import_cache.dart';
import 'costume_domains_cache.dart';
import 'hierarchy_cache.dart';
import 'scene_shoot_cache.dart';
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
    CostumeCacheRows,
    CharacterCacheRows,
    ShootingDayCacheRows,
    SceneShootCacheRows,
    AiImportJobCacheRows,
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
  int get schemaVersion => 6;

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
      if (from < 3) {
        // `flutter-costume-domains` 1.1: costume-domain projection tables
        // (costumes, characters, shooting_days). Fresh tables for existing
        // installs — no data to migrate. Photo bytes are memory-cached
        // only, never persisted (design §3).
        await m.createTable(costumeCacheRows);
        await m.createTable(characterCacheRows);
        await m.createTable(shootingDayCacheRows);
      }
      // Guarded by `from == 3` (not `< 4`): older databases enter the
      // `from < 3` branch above, which creates the costume table from the
      // CURRENT definition — already including the column — so a second
      // ADD COLUMN would fail with `duplicate column name`. Only a real
      // v3 database (table exists, column missing) needs the ALTER.
      if (from < 5) {
        // `flutter-shoot-day-execution` 1.2: day-board projection table
        // (scene shoots mirroring `SceneShootView`). Fresh table for
        // existing installs — no data to migrate. Photo bytes stay
        // memory-cached only, never persisted (design §3).
        await m.createTable(sceneShootCacheRows);
      }
      if (from < 6) {
        // `flutter-ai-import` 1.4: AI-import job projection table
        // (mirrors `AiImportJob`; carries the client-local persisted
        // apply context columns `episode_id`/`series_id`, design §2.3).
        // Fresh table for existing installs — no data to migrate.
        // NOTE: the table is defined in `ai_import_cache.dart` (no
        // `cache_database` import — a cycle would break drift_dev table
        // discovery); its DAO lives in `ai_import_jobs_cache_dao.dart`.
        await m.createTable(aiImportJobCacheRows);
      }
      if (from == 3) {
        // CodeRabbit review follow-up: snapshot ordinal on the costume rows
        // so `readBySeason` reproduces the server `ORDER BY updated_at
        // DESC` exactly. Plain `m.addColumn` emits `ADD COLUMN ... NOT
        // NULL` without a default, which SQLite rejects on populated v3
        // tables (and would otherwise leave NULLs the non-nullable Dart
        // mapping cannot read) — so the statement carries `DEFAULT 0`
        // explicitly. The next snapshot replaces all rows anyway.
        await m.database.customStatement(
          'ALTER TABLE costume_cache_rows '
          'ADD COLUMN snapshot_index INTEGER NOT NULL DEFAULT 0',
        );
      }
    },
  );
}
