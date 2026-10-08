// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

// Migration probe for the v12 → v13 upgrade (issue #599, ADR-035 D1/S1
// layer 3): the `SeriesId` → `ProjectId` rename completed its wire/storage
// layer, so `SeasonView`/`BlockView`/`EpisodeView` and the AI-import apply
// context carry `project_id` and the mirrored cache columns follow.
//
// The migration is deliberately **additive, not a rename** (the cache policy
// in `cache_database.dart` forbids destructive migrations and the cache is
// snapshot-replace by design): an install that reaches v13 still has its
// orphaned `series_id` column and gains a `project_id` one. This probe pins
// that contract — the ADD COLUMN must succeed on a populated v12 table
// (SQLite rejects a bare `NOT NULL` on one, hence the explicit default), the
// pre-existing rows must survive, and the DAOs must read the new column.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';

/// A v12 install: the current schema minus the `project_id` columns, with
/// `user_version` pinned back to 12. Built by DROP-and-recreate (same trick as
/// the v10 → v11 probe) so the tables genuinely have the old shape.
Future<void> _emulateV12(CacheDatabase db) async {
  await db.customStatement('DROP TABLE season_cache_rows');
  await db.customStatement(
    'CREATE TABLE season_cache_rows ('
    'id TEXT NOT NULL PRIMARY KEY, number INTEGER NOT NULL, archived INTEGER '
    'NOT NULL, series_id TEXT NOT NULL, title TEXT, updated_at INTEGER NOT '
    'NULL, version INTEGER NOT NULL, cached_at INTEGER NOT NULL)',
  );
  await db.customStatement('DROP TABLE block_cache_rows');
  await db.customStatement(
    'CREATE TABLE block_cache_rows ('
    'id TEXT NOT NULL PRIMARY KEY, season_id TEXT NOT NULL, series_id TEXT '
    'NOT NULL, number INTEGER NOT NULL, start_date TEXT, end_date TEXT, '
    'updated_at INTEGER NOT NULL, version INTEGER NOT NULL, cached_at INTEGER '
    'NOT NULL)',
  );
  await db.customStatement(
    "INSERT INTO season_cache_rows (id, number, archived, series_id, title, "
    "updated_at, version, cached_at) VALUES ('s1', 1, 0, 'legacy-project', "
    "NULL, 1136073600000, 1, 1136073600000)",
  );
  await db.customStatement(
    "INSERT INTO block_cache_rows (id, season_id, series_id, number, "
    "start_date, end_date, updated_at, version, cached_at) VALUES ('b1', "
    "'s1', 'legacy-project', 1, NULL, NULL, 1136073600000, 1, 1136073600000)",
  );
  await db.customStatement('PRAGMA user_version = 12');
}

void main() {
  test(
    'v12 → v13: the project_id columns are added on upgrade; rows survive',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/project_id_migration_'
        '${DateTime.now().microsecondsSinceEpoch}.db',
      );
      addTearDown(() => file.deleteSync());

      // 1. Emulate a v12 install with populated rows.
      final v12 = CacheDatabase(NativeDatabase(file));
      await _emulateV12(v12);
      await v12.close();

      // 2. Reopen at v13: the `from < 13` branch adds `project_id` (with an
      //    explicit default on the NOT NULL columns) and leaves `series_id` in
      //    place — nothing is dropped, per the cache's no-destructive-migration
      //    policy.
      final v13 = CacheDatabase(NativeDatabase(file));
      addTearDown(v13.close);

      final columns =
          (await v13
                  .customSelect(
                    "SELECT name FROM pragma_table_info('season_cache_rows')",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(
        columns,
        containsAll(<String>['project_id', 'series_id']),
        reason: 'the new column must be added without dropping the old one',
      );

      // 3. The witness rows survive and read through the DAOs. `project_id`
      //    carries the migration default (`''`) until the next snapshot-replace
      //    refills it from the server projection — never a NOT NULL crash.
      final seasons = await SeasonCacheDao(v13).readAll();
      expect(seasons.single.id, 's1');
      final blocks = await BlockCacheDao(v13).readBySeason('s1');
      expect(blocks.single.id, 'b1');

      // 4. The nullable AI-import column uses the plain addColumn path and is
      //    readable as NULL (absent apply context), not dropped.
      await AiImportJobsCacheDao(v13).upsertAll(const [], DateTime.utc(2026));
      final aiColumns =
          (await v13
                  .customSelect(
                    "SELECT name FROM pragma_table_info('ai_import_job_cache_rows')",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(aiColumns, contains('project_id'));
    },
  );
}
