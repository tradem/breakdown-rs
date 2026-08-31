// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';

SeasonView _season(
  String id, {
  int number = 1,
  String? title,
  DateTime? updatedAt,
}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = updatedAt ?? DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('SeasonCacheDao', () {
    late CacheDatabase db;
    late SeasonCacheDao dao;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      dao = SeasonCacheDao(db);
    });

    tearDown(() => db.close());

    // Task 2.3 — cache upsert + read round-trips; server field preserved.
    test('upsert then readAll round-trips a SeasonView', () async {
      final view = _season('s1', title: 'Spring');
      await dao.upsert(view, DateTime.utc(2026, 2, 1));

      final rows = await dao.readAll();
      expect(rows, hasLength(1));
      expect(rows.first.id, 's1');
      expect(rows.first.title, 'Spring');
      expect(rows.first.seriesId, 'series-1');
      expect(rows.first.updatedAt, DateTime.utc(2026, 1, 1));
      expect(rows.first.version, 1);
    });

    test('upsert overwrites the same id (idempotent by id)', () async {
      await dao.upsert(
        _season('s1', title: 'Spring'),
        DateTime.utc(2026, 2, 1),
      );
      await dao.upsert(
        _season('s1', title: 'Spring II'),
        DateTime.utc(2026, 2, 2),
      );

      final rows = await dao.readAll();
      expect(rows, hasLength(1));
      expect(rows.first.title, 'Spring II');
    });

    test('readById returns null for an unknown id', () async {
      expect(await dao.readById('nope'), isNull);
    });

    // Task 2.4 / D3 — snapshot-replace deletes missing ids in one transaction.
    test(
      'applySnapshot deletes cached rows absent from the returned set',
      () async {
        await dao.applySnapshot([
          _season('a'),
          _season('b'),
          _season('c'),
        ], DateTime.utc(2026, 2, 1));
        expect((await dao.readAll()).map((r) => r.id).toList(), [
          'a',
          'b',
          'c',
        ]);

        // Server now reports only a and b → c must be deleted, not orphaned.
        await dao.applySnapshot([
          _season('a'),
          _season('b'),
        ], DateTime.utc(2026, 2, 2));
        expect((await dao.readAll()).map((r) => r.id).toList(), ['a', 'b']);
      },
    );

    test('applySnapshot with an empty list clears the table', () async {
      await dao.applySnapshot([
        _season('a'),
        _season('b'),
      ], DateTime.utc(2026, 2, 1));
      await dao.applySnapshot([], DateTime.utc(2026, 2, 2));
      expect(await dao.readAll(), isEmpty);
    });

    // Task 3.1 — TTL computed from cachedAt via the DAO.
    test('isAnyExpired reflects cachedAt under the injectable clock', () async {
      await dao.upsert(_season('s1'), DateTime.utc(2026, 1, 1));
      final nowFresh = DateTime.utc(2026, 1, 1, 1); // 1h later
      expect(
        await dao.isAnyExpired(kCacheTtl, clock: Clock.fixed(nowFresh)),
        isFalse,
      );

      final nowStale = DateTime.utc(2026, 1, 3); // 2 days later
      expect(
        await dao.isAnyExpired(kCacheTtl, clock: Clock.fixed(nowStale)),
        isTrue,
      );
    });
  });
}
