// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Migration probe for the `flutter-ai-import` v5 → v6 upgrade (task 1.4):
// an install opened at schemaVersion 5 (no `ai_import_job_cache_rows`
// table) migrates to v6 by creating the fresh table — no data to migrate,
// and existing rows survive.

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';

/// A CacheDatabase that reports schemaVersion 5 and excludes the v6 table
/// from `createAll` — emulating an install from before this change.
class _ProbeDatabaseV5 extends CacheDatabase {
  _ProbeDatabaseV5(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => super.allSchemaEntities
      .where((entity) => entity != aiImportJobCacheRows)
      .toList();
}

AiImportJob _job(String id) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'user-a'
    ..status = JobStatus.pending
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

void main() {
  test('v5 → v6: the AI-import job table is created on upgrade; existing '
      'rows survive', () async {
    final file = File(
      '${Directory.systemTemp.path}/ai_migration_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() => file.deleteSync());

    // 1. App installed at v5: the nine pre-AI tables exist and hold a row
    //    in the seasons table (survival witness).
    final v5 = _ProbeDatabaseV5(NativeDatabase(file));
    await v5.customStatement(
      "INSERT INTO season_cache_rows (id, number, archived, series_id, "
      "updated_at, version, cached_at) VALUES ('s1', 1, 0, 'series-1', "
      "'2026-01-01T00:00:00.000Z', 1, '2026-01-01T00:00:00.000Z')",
    );
    await v5.close();

    // 2. App upgraded to v6: reopening the same file runs the `from < 6`
    //    migration branch — the fresh AI jobs table is created and usable,
    //    and the pre-existing row survived untouched.
    final v6 = CacheDatabase(NativeDatabase(file));
    addTearDown(v6.close);
    final dao = AiImportJobsCacheDao(v6);
    await dao.upsertAll([_job('j1')], DateTime.utc(2026, 1, 2));
    expect((await dao.readAll('user-a')).single.id, 'j1');

    // The v5 witness row is still there (nothing was dropped/recreated).
    final seasons = await v6
        .customSelect('SELECT id FROM season_cache_rows')
        .get();
    expect(seasons.single.read<String>('id'), 's1');
  });

  /// Issue #533 regression probe for the REAL v10 → v11 ALTER path: an install
  /// whose `season_cache_rows` table genuinely lacks the `archived` column
  /// (the v10 shape) gains the column through the `from < 11` migration branch
  /// — existing rows read `archived = false`, never a NOT NULL crash.
  test('v10 → v11: the season archived column is added on upgrade; rows '
      'survive', () async {
    final file = File(
      '${Directory.systemTemp.path}/season_migration_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() => file.deleteSync());

    // 1. Emulate a v10 install: create the current schema, then DROP the new
    //    column and pin the version back to 10 — the honest v10 table shape.
    final v10 = CacheDatabase(NativeDatabase(file));
    await v10.customStatement('DROP TABLE season_cache_rows');
    await v10.customStatement(
      'CREATE TABLE season_cache_rows ('
      'id TEXT NOT NULL PRIMARY KEY, number INTEGER NOT NULL, '
      "series_id TEXT NOT NULL, title TEXT, updated_at INTEGER NOT NULL, "
      'version INTEGER NOT NULL, cached_at INTEGER NOT NULL)',
    );
    await v10.customStatement('PRAGMA user_version = 10');
    await v10.customStatement(
      "INSERT INTO season_cache_rows (id, number, series_id, title, "
      "updated_at, version, cached_at) VALUES ('s1', 1, 'series-1', NULL, "
      "1136073600000, 1, 1136073600000)",
    );
    await v10.close();

    // 2. Reopen at v11: the `from < 11` branch ALTERs the column in
    //    (DEFAULT 0), and the DAO reads the row with archived = false.
    final v11 = CacheDatabase(NativeDatabase(file));
    addTearDown(v11.close);
    final dao = SeasonCacheDao(v11);
    final rows = await dao.readAll();
    expect(rows.single.id, 's1');
    expect(
      rows.single.archived,
      isFalse,
      reason:
          'the migrated row must read un-archived, not crash on the '
          'NOT NULL column',
    );
  });
}
