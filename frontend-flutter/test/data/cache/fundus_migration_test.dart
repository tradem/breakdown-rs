// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Migration probe for the v13 → v14 upgrade (issue #625,
// `flutter-fundus-search`): the project-scoped fundus cache slice is a fresh
// table (`createTable`, no data to migrate). This probe pins that the
// upgrade creates it on an install that predates it, that pre-existing rows
// survive, and that the new DAO can read/write it.

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';

void main() {
  test(
    'v13 → v14: the fundus table is created; existing rows survive',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/fundus_migration_'
        '${DateTime.now().microsecondsSinceEpoch}.db',
      );
      addTearDown(() => file.deleteSync());

      // 1. A v14 install, then emulate v13 by dropping the (fresh) fundus
      //    table and pinning user_version back to 13. With from == 13, ONLY
      //    the `from < 14` branch runs on the next open (every other branch is
      //    `from < N` with N <= 13), so the probe exercises exactly the new
      //    migration.
      final seeded = CacheDatabase(NativeDatabase(file));
      await SeasonCacheDao(seeded).applySnapshot([
        SeasonView(
          (b) => b
            ..archived = false
            ..id = 's1'
            ..number = 1
            ..projectId = 'project-1'
            ..title = 'Staffel Eins'
            ..updatedAt = DateTime.utc(2026, 1, 1)
            ..version = 1,
        ),
      ], DateTime.utc(2026, 1, 1, 10));
      await seeded.customStatement('DROP TABLE fundus_costume_cache_rows');
      await seeded.customStatement('PRAGMA user_version = 13');
      await seeded.close();

      // 2. Reopen at v14: the migration creates the fundus table.
      final upgraded = CacheDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final columns =
          (await upgraded
                  .customSelect(
                    "SELECT name FROM pragma_table_info('fundus_costume_cache_rows')",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(columns, contains('project_id'));
      expect(columns, contains('season_ids_json'));

      // 3. Existing rows survive.
      expect((await SeasonCacheDao(upgraded).readAll()).single.id, 's1');

      // 4. The new DAO can write and read through the migrated table.
      final dao = FundusCostumeCacheDao(upgraded);
      await dao.applySnapshotForProject('project-1', [
        CostumeView(
          (b) => b
            ..id = 'k1'
            ..notes = 'Jacke'
            ..details.replace(BuiltList<CostumeDetailView>())
            ..photos.replace(BuiltList<CostumePhotoView>())
            ..seasonIds.replace(BuiltList<String>(['s1']))
            ..updatedAt = DateTime.utc(2026, 1, 1)
            ..version = 1,
        ),
      ], DateTime.utc(2026, 1, 1, 10));
      final rows = await dao.readByProjectFresh('project-1');
      expect(rows.rows.single.id, 'k1');
    },
  );
}
