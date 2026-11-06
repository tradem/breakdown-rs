// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit tests for `aiImportSeasonView` (issue #828): the target card's
// create action needs the target season's ROW (the shared create-block form
// takes a `SeasonView` and pre-fills its command ids from it). The provider is
// cache-first and fetches through the repository only on a miss — these tests
// pin both branches, the Err arms, and the "no guessed id" contract (a row that
// cannot be read stays `null`, so the card reports it instead of opening a form
// it cannot fill).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_target.dart';

SeasonView _season(String id, {int number = 2}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..projectId = 'project-1'
    ..title = 'Season'
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

const _notFound = ProblemError(code: 'season.not-found', status: 404);
const _cacheDown = ProblemError(code: 'cache.read_failed');

/// Season repository fake: the two surfaces `aiImportSeasonView` touches
/// (`readCached`, `getAndCache`) are scriptable, everything else is untouched.
class _FakeSeasonRepository extends SeasonRepository {
  _FakeSeasonRepository(super.api, super.cache);

  Result<List<SeasonView>> cached = const Right([]);
  Result<SeasonView>? fetched;
  int fetchCalls = 0;
  final List<String> fetchedIds = [];

  @override
  Future<Result<List<SeasonView>>> readCached() async => cached;

  @override
  Future<Result<SeasonView>> getAndCache(
    String id, {
    Clock clock = Clock.system,
  }) {
    fetchCalls++;
    fetchedIds.add(id);
    return Future.value(fetched ?? const Left(_notFound));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeSeasonRepository repo;
  late ProviderContainer container;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    repo = _FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    container = ProviderContainer(
      overrides: [seasonRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<SeasonView?> resolve(String seasonId) =>
      container.read(aiImportSeasonViewProvider(seasonId).future);

  test('a cached row answers WITHOUT a network fetch', () async {
    repo.cached = Right([_season('season-1', number: 7)]);

    final row = await resolve('season-1');

    expect(row?.id, 'season-1');
    expect(row?.number, 7);
    expect(repo.fetchCalls, 0, reason: 'the cache is the normal case');
  });

  test(
    'a cache miss fetches the row through the repository and caches it',
    () async {
      repo.cached = const Right([]);
      repo.fetched = Right(_season('season-miss', number: 4));

      final row = await resolve('season-miss');

      expect(row?.id, 'season-miss');
      expect(row?.number, 4);
      expect(repo.fetchCalls, 1);
      expect(repo.fetchedIds, [
        'season-miss',
      ], reason: 'the ids come from the acted-on season — never from a guess');
    },
  );

  test(
    'a cache hit for ANOTHER season is a miss (no cross-season row)',
    () async {
      repo.cached = Right([_season('season-other', number: 9)]);
      repo.fetched = Right(_season('season-1', number: 2));

      final row = await resolve('season-1');

      expect(row?.id, 'season-1', reason: 'the row must match the asked id');
      expect(repo.fetchCalls, 1);
    },
  );

  test(
    'a failed fetch yields null — the card reports it, never a guessed row',
    () async {
      repo.cached = const Right([]);
      repo.fetched = const Left(_notFound);

      expect(await resolve('season-1'), isNull);
      expect(repo.fetchCalls, 1);
    },
  );

  test(
    'an unreadable cache still falls through to the fetch (Err arm)',
    () async {
      repo.cached = const Left(_cacheDown);
      repo.fetched = Right(_season('season-1'));

      final row = await resolve('season-1');

      expect(row?.id, 'season-1');
      expect(repo.fetchCalls, 1);
    },
  );
}
