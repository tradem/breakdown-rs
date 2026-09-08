// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Migration tests (CodeRabbit re-review P1): the v3 → v4 upgrade backfills
// the costume snapshot ordinal. Without the backfill, pre-existing v3 rows
// carry NULL for a non-nullable Dart field and every offline cache read
// after upgrade fails before the next snapshot replaces them.
//
// The test simulates a v3 install with raw SQL on a temp file (v3 table
// shape without the column, one populated row, user_version = 3), then
// opens it through CacheDatabase and asserts the row stays readable.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';

/// Minimal opener marking the file as a v3 install (schema marker only;
/// the v3 table shape is created with raw SQL afterwards).
/// Minimal opener marking the file as a v2 install (schema marker only;
/// v2 tables are created with raw SQL afterwards; the v3/v4 tables are
/// created by the migration itself).
class _V2Install implements QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

class _V3Install implements QueryExecutorUser {
  @override
  int get schemaVersion => 3;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// Minimal opener marking the file as a v4 install (schema marker only;
/// the v4 table shapes are created with raw SQL afterwards; the v5
/// day-board table is created by the migration itself).
class _V4Install implements QueryExecutorUser {
  @override
  int get schemaVersion => 4;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  test('v3 to v4 migration backfills the snapshot ordinal', () async {
    final dir = await Directory.systemTemp.createTemp('costume-migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.db');

    // A v3 install: costume table WITHOUT snapshot_index, one populated
    // row, schema marker at 3 (timestamps are opaque ints here — the DAO
    // decodes them without crashing regardless of unit).
    final setup = NativeDatabase(file);
    await setup.ensureOpen(_V3Install());
    await setup.runCustom(
      'CREATE TABLE costume_cache_rows ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'season_id TEXT NOT NULL, '
      'character_id TEXT NULL, '
      'notes TEXT NOT NULL, '
      'details_json TEXT NOT NULL, '
      'photos_json TEXT NOT NULL, '
      'updated_at INTEGER NOT NULL, '
      'version INTEGER NOT NULL, '
      'cached_at INTEGER NOT NULL)',
    );
    await setup.runCustom(
      "INSERT INTO costume_cache_rows VALUES "
      "('c-1', 's-1', NULL, 'notes', '[]', '[]', 1767225600, 1, 1767225600)",
    );
    await setup.close();

    // Opening through the app database runs only the v3 → v4 branch.
    final db = CacheDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final dao = CostumeCacheDao(db);
    final rows = await dao.readBySeason('s-1');
    expect(rows.map((c) => c.id), ['c-1']);
    expect(rows.single.version, 1);

    // A fresh snapshot still applies cleanly on the migrated schema.
    await dao.applySnapshotForSeason('s-1', rows, DateTime.utc(2026, 1, 2));
    expect((await dao.readBySeason('s-1')).map((c) => c.id), ['c-1']);
  });

  test(
    'populated v2 to v4 keeps season rows and creates costume tables',
    () async {
      final dir = await Directory.systemTemp.createTemp('costume-migration-v2');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.db');

      // A v2 install: only the v2 tables exist (seasons populated here; the
      // hierarchy tables are created empty by the migration itself, which is
      // exactly what the from < 2 / from < 3 branches cover).
      final setup = NativeDatabase(file);
      await setup.ensureOpen(_V2Install());
      await setup.runCustom(
        'CREATE TABLE season_cache_rows ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'number INTEGER NOT NULL, '
        'series_id TEXT NOT NULL, '
        'title TEXT NULL, '
        'updated_at INTEGER NOT NULL, '
        'version INTEGER NOT NULL, '
        'cached_at INTEGER NOT NULL)',
      );
      await setup.runCustom(
        "INSERT INTO season_cache_rows VALUES "
        "('s-1', 1, 'series-1', NULL, 1767225600, 1, 1767225600)",
      );
      await setup.close();

      // Upgrade v2 → v4: hierarchy + costume tables are created from the
      // current definitions (already carrying snapshot_index), so the ALTER
      // must NOT run again (duplicate column). The season row survives.
      final db = CacheDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect((await SeasonCacheDao(db).readAll()).map((s) => s.id), ['s-1']);
      final dao = CostumeCacheDao(db);
      expect(await dao.readBySeason('s-1'), isEmpty);
    },
  );

  test('v4 to v5 creates the day-board table, season rows survive', () async {
    final dir = await Directory.systemTemp.createTemp('sceneshoot-migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.db');

    // A v4 install: seasons populated, no scene-shoot table yet.
    final setup = NativeDatabase(file);
    await setup.ensureOpen(_V4Install());
    await setup.runCustom(
      'CREATE TABLE season_cache_rows ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'number INTEGER NOT NULL, '
      'series_id TEXT NOT NULL, '
      'title TEXT NULL, '
      'updated_at INTEGER NOT NULL, '
      'version INTEGER NOT NULL, '
      'cached_at INTEGER NOT NULL)',
    );
    await setup.runCustom(
      "INSERT INTO season_cache_rows VALUES "
      "('s-1', 1, 'series-1', NULL, 1767225600, 1, 1767225600)",
    );
    await setup.close();

    // Upgrade v4 → v5: the day-board table is created from the current
    // definition; the season row survives; snapshots apply cleanly.
    final db = CacheDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await SeasonCacheDao(db).readAll()).map((s) => s.id), ['s-1']);
    final dao = SceneShootCacheDao(db);
    expect(await dao.readByDayOrdered('day-1'), isEmpty);
  });
}
