// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Migration tests (CodeRabbit re-review P1): the v3 → v4 upgrade backfills
// the piece snapshot ordinal. Without the backfill, pre-existing v3 rows
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

import 'package:breakdown_api/breakdown_api.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';

/// Minimal opener marking the file as a v3 install (schema marker only;
/// the v3 table shape is created with raw SQL afterwards).
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
  test('a v3 install keeps climbing to the wardrobe schema', () async {
    final dir = await Directory.systemTemp.createTemp('piece-migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.db');

    // A v3 install: the RETIRED piece snapshot table, one populated row,
    // schema marker at 3.
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

    // Opening through the app database climbs to the current schema. The
    // wardrobe split (v16) drops the piece snapshot table wholesale: the
    // `PieceView` DTO no longer exists, so its rows can never be read
    // again. The successor piece slice starts empty and fills on the next
    // TTL snapshot-replace (design D3: the backend is authoritative).
    final db = CacheDatabase(NativeDatabase(file));
    addTearDown(db.close);
    // v17 (issue #763) adds the nullable AI-import job identity columns
    // (`source_file_name`, `applied_episodes_json`) — again additive only.
    // v18 (issue #767) adds the nullable AI-import `decision_telemetry_json`
    // column — additive, never destructive.
    expect(db.schemaVersion, 18);
    final dao = PieceCacheDao(db);
    expect(await dao.readBySeason('s-1'), isEmpty);

    // A fresh snapshot applies cleanly on the migrated schema.
    await dao.applySnapshotForSeason('s-1', [
      PieceView(
        (b) => b
          ..name = 'Fundus-Piece'
          ..id = 'c-1'
          ..notes = 'notes'
          ..details.replace(const [])
          ..photos.replace(const [])
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      ),
    ], DateTime.utc(2026, 1, 2));
    expect((await dao.readBySeason('s-1')).map((c) => c.id), ['c-1']);
  });

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
      'project_id TEXT NOT NULL, '
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
