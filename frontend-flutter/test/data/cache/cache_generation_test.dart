// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/season_repository.dart';

import '../../features/seasons/seasons_test_fakes.dart';

/// Generation-fence tests (task 6.3): a fetch that started before a reset
/// must not persist rows from the old identity/backend afterwards.
void main() {
  late CacheDatabase db;
  late SeasonRepository repo;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = SeasonRepository(BreakdownApi(), SeasonCacheDao(db));
  });

  group('CacheWriteFence', () {
    test('stale generation: rows returned, never persisted', () async {
      var current = 7;
      final fence = CacheWriteFence(
        generation: 7,
        isCurrentGeneration: (g) => g == current,
      );
      final rows = [season('fenced', number: 1)];

      // A base switch / sign-out lands while the fetch is in flight.
      current = 8;

      final result = await repo.fetchAndCacheList(
        () async => Right(rows),
        fence: fence,
      );

      // Discarded, not persisted: caller keeps the rows, cache stays empty.
      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable()?.map((row) => row.id).toList(), [
        'fenced',
      ]);
      expect(await SeasonCacheDao(db).readAll(), isEmpty);
    });

    test('current generation: snapshot applies normally', () async {
      const current = 7;
      final fence = CacheWriteFence(
        generation: 7,
        isCurrentGeneration: (g) => g == current,
      );

      final result = await repo.fetchAndCacheList(
        () async => Right([season('kept', number: 1)]),
        fence: fence,
      );

      expect(result.isRight(), isTrue);
      expect((await SeasonCacheDao(db).readAll()).map((s) => s.id), ['kept']);
    });

    test('generation provider starts at zero and bumps', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(cacheGenerationProvider), 0);
      container.read(cacheGenerationProvider.notifier).bump();
      container.read(cacheGenerationProvider.notifier).bump();
      expect(container.read(cacheGenerationProvider), 2);
    });
  });
}
