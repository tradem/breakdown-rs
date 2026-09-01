// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/season_repository.dart';

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

const _err = ProblemError(code: 'season.not_found');

void main() {
  group('SeasonRepository cache path', () {
    late CacheDatabase db;
    late SeasonRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = SeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    });

    tearDown(() => db.close());

    // Task 2.1 — successful fetch upserts into Drift; the screen can read it.
    test('getAndCacheFrom on Right upserts the row into the cache', () async {
      final res = await repo.getAndCacheFrom(
        Right(_season('s1', title: 'Spring')),
      );
      expect(res, isA<Right>());

      final cached = await repo.readCached();
      expect(cached, isA<Right>());
      expect((cached as Right).value.map((v) => v.id).toList(), ['s1']);
    });

    // Task 2.1 + 3.3 — a fetch error must NOT mutate the cache (no partial
    // writes), and must surface the error rather than throwing.
    test(
      'getAndCacheFrom on Left leaves the cache untouched and returns Err',
      () async {
        await repo.getAndCacheFrom(Right(_season('s1')));

        final res = await repo.getAndCacheFrom(const Left(_err));
        expect(res, const Left(_err));

        // The failed refetch must not have deleted or altered the cached row.
        final cached = await repo.readCached();
        expect((cached as Right).value.map((v) => v.id).toList(), ['s1']);
      },
    );

    // Task 2.4 / D3 — list fetch snapshot-replace at the repository boundary.
    test(
      'fetchAndCacheList applies snapshot-replace and never deletes on Err',
      () async {
        final ok1 = await repo.fetchAndCacheList(
          () async => Right([_season('a'), _season('b'), _season('c')]),
        );
        expect(ok1, isA<Right>());
        expect((await repo.readCached() as Right).value.map((v) => v.id), [
          'a',
          'b',
          'c',
        ]);

        // Server drops c → snapshot-replace deletes it.
        final ok2 = await repo.fetchAndCacheList(
          () async => Right([_season('a'), _season('b')]),
        );
        expect(ok2, isA<Right>());
        expect((await repo.readCached() as Right).value.map((v) => v.id), [
          'a',
          'b',
        ]);

        // A failed refetch must NOT delete cached rows (D3: delete only on a
        // complete, successful snapshot).
        final err = await repo.fetchAndCacheList(() async => const Left(_err));
        expect(err, const Left(_err));
        expect((await repo.readCached() as Right).value.map((v) => v.id), [
          'a',
          'b',
        ]);
      },
    );
  });

  group('SeasonRepository.list (first-screen-seasons Task 2.2)', () {
    late CacheDatabase db;
    late SeasonRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = SeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    });

    tearDown(() => db.close());

    // Ok branch: pure Drift read of the projected rows (the screen's
    // authoritative read surface).
    test('returns cached rows on Ok', () async {
      await repo.fetchAndCacheList(
        () async => Right([_season('a'), _season('b')]),
      );

      final res = await repo.list();
      expect(res, isA<Right>());
      expect((res as Right).value.map((v) => v.id), ['a', 'b']);
    });

    // Err branch: a cache read failure is a Result, never a throw
    // (AGENTS.md §5: no throw in data/).
    test(
      'returns Err(code: cache.read_failed) when the cache is unavailable',
      () async {
        final failingRepo = SeasonRepository(
          BreakdownApi(),
          _ThrowingCacheDao(db),
        );

        final res = await failingRepo.list();
        expect(res, isA<Left>());
        expect((res as Left).value.code, 'cache.read_failed');
      },
    );
  });
}

/// DAO fake whose reads fail at the executor level, exercising the
/// repository's `Left(ProblemError)` translation.
class _ThrowingCacheDao extends SeasonCacheDao {
  _ThrowingCacheDao(super.db);

  @override
  Future<List<SeasonView>> readAll() async =>
      throw StateError('simulated executor failure');
}
