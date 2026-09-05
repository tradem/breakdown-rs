// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/data/episode_repository.dart';
import 'package:frontend_flutter/data/scene_repository.dart';

BlockView _block(String id, {String seasonId = 'season-1', int number = 1}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = seasonId
        ..seriesId = 'series-1'
        ..startDate = '2026-01-01'
        ..endDate = '2026-01-31'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

EpisodeView _episode(
  String id, {
  String blockId = 'block-1',
  int number = 1,
  String? name,
}) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = blockId
    ..name = name
    ..number = number
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _scene(
  String id, {
  String episodeId = 'episode-1',
  List<String> characters = const [],
  List<String> shootingDays = const [],
}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = episodeId
    ..assignedCharacters.replace(characters)
    ..isScheduleSet = false
    ..location = 'Studio A'
    ..mood = 'tense'
    ..scriptDay = 'Day 1'
    ..shootingDayIds.replace(shootingDays)
    ..summary = 'A scene'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

CostumeCategoryView _category(
  String id, {
  String seasonId = 'season-1',
  String name = 'Cat',
  String orderKey = '!',
  bool archived = false,
}) => CostumeCategoryView(
  (b) => b
    ..id = id
    ..seasonId = seasonId
    ..name = name
    ..orderKey = orderKey
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

IdVersionResponse _ack(String id) => IdVersionResponse(
  (b) => b
    ..id = id
    ..version = 1,
);

const _err = ProblemError(code: 'transport.connectionError');

/// Repository fake: [runList]/[run] are scriptable; everything else runs the
/// real (cache-backed) implementation so cache-touch/untouched assertions
/// are meaningful.
class FakeBlockRepository extends BlockRepository {
  FakeBlockRepository(super.api, super.cache);

  Result<List<BlockView>>? nextList;
  Result<IdVersionResponse>? nextCreate;

  @override
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    final scripted = nextList;
    if (T == BlockView && scripted != null) {
      return scripted as Result<List<T>>;
    }
    return super.runList(call, dtoInvalidCode: dtoInvalidCode);
  }

  @override
  Future<Result<T>> run<T>(
    Future<Response<T>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    if (T == IdVersionResponse && nextCreate != null) {
      return nextCreate as Result<T>;
    }
    return super.run(call);
  }
}

class FakeEpisodeRepository extends EpisodeRepository {
  FakeEpisodeRepository(super.api, super.cache);

  Result<List<EpisodeView>>? nextList;
  Result<IdVersionResponse>? nextCreate;

  @override
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    final scripted = nextList;
    if (T == EpisodeView && scripted != null) {
      return scripted as Result<List<T>>;
    }
    return super.runList(call, dtoInvalidCode: dtoInvalidCode);
  }

  @override
  Future<Result<T>> run<T>(
    Future<Response<T>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    if (T == IdVersionResponse && nextCreate != null) {
      return nextCreate as Result<T>;
    }
    return super.run(call);
  }
}

class FakeSceneRepository extends SceneRepository {
  FakeSceneRepository(super.api, super.cache);

  Result<List<SceneView>>? nextList;
  Result<IdVersionResponse>? nextCreate;

  @override
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    final scripted = nextList;
    if (T == SceneView && scripted != null) {
      return scripted as Result<List<T>>;
    }
    return super.runList(call, dtoInvalidCode: dtoInvalidCode);
  }

  @override
  Future<Result<T>> run<T>(
    Future<Response<T>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    if (T == IdVersionResponse && nextCreate != null) {
      return nextCreate as Result<T>;
    }
    return super.run(call);
  }
}

class FakeCostumeCategoryRepository extends CostumeCategoryRepository {
  FakeCostumeCategoryRepository(super.api, super.cache);

  Result<List<CostumeCategoryView>>? nextList;
  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;

  @override
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    final scripted = nextList;
    if (T == CostumeCategoryView && scripted != null) {
      return scripted as Result<List<T>>;
    }
    return super.runList(call, dtoInvalidCode: dtoInvalidCode);
  }

  @override
  Future<Result<T>> run<T>(
    Future<Response<T>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    if (T == IdVersionResponse && nextCreate != null) {
      return nextCreate as Result<T>;
    }
    if (T == int && nextWrite != null) {
      return nextWrite as Result<T>;
    }
    return super.run(call);
  }
}

void main() {
  group('hierarchy cache schema (2.1)', () {
    test('schema version is 2 with all four projection tables', () async {
      final db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, 2);
      // Every table round-trips (migration created them).
      await BlockCacheDao(db).applySnapshotForSeason('s', [
        _block('b', seasonId: 's'),
      ], DateTime.utc(2026, 1, 1));
      await EpisodeCacheDao(db).applySnapshotForBlock('b', [
        _episode('e', blockId: 'b'),
      ], DateTime.utc(2026, 1, 1));
      await SceneCacheDao(db).applySnapshotForEpisode('e', [
        _scene('s', episodeId: 'e'),
      ], DateTime.utc(2026, 1, 1));
      await CostumeCategoryCacheDao(db).applySnapshotForSeason('s', [
        _category('c', seasonId: 's'),
      ], DateTime.utc(2026, 1, 1));
      expect((await BlockCacheDao(db).readBySeason('s')).map((v) => v.id), [
        'b',
      ]);
      expect((await EpisodeCacheDao(db).readByBlock('b')).map((v) => v.id), [
        'e',
      ]);
      expect((await SceneCacheDao(db).readByEpisode('e')).map((v) => v.id), [
        's',
      ]);
      final catRows = await CostumeCategoryCacheDao(db)
          .readBySeasonOrdered('s');
      expect(catRows.map((v) => v.id), ['c']);
    });
  });

  group('pruneOrphanedHierarchyRows + expiry (D5/TTL)', () {
    late CacheDatabase db;

    setUp(() => db = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('drops orphaned subtree rows, keeps live ones', () async {
      final at = DateTime.utc(2026, 1, 1);
      await BlockCacheDao(db).applySnapshotForSeason('s-live', [
        _block('b-keep', seasonId: 's-live'),
      ], at);
      await BlockCacheDao(db).applySnapshotForSeason('s-gone', [
        _block('b-drop', seasonId: 's-gone'),
      ], at);
      await EpisodeCacheDao(db).applySnapshotForBlock('b-keep', [
        _episode('e-keep', blockId: 'b-keep'),
      ], at);
      await EpisodeCacheDao(db).applySnapshotForBlock('b-drop', [
        _episode('e-drop', blockId: 'b-drop'),
      ], at);

      await pruneOrphanedHierarchyRows(
        db,
        liveSeasonIds: {'s-live'},
        liveBlockIds: {'b-keep'},
        liveEpisodeIds: const {},
      );

      expect(
        (await BlockCacheDao(db).readBySeason('s-live')).map((v) => v.id),
        ['b-keep'],
      );
      expect(await BlockCacheDao(db).readBySeason('s-gone'), isEmpty);
      expect(
        (await EpisodeCacheDao(db).readByBlock('b-keep')).map((v) => v.id),
        ['e-keep'],
      );
      expect(await EpisodeCacheDao(db).readByBlock('b-drop'), isEmpty);
    });

    test(
      'successful empty parent snapshot clears the whole child scope',
      () async {
        final at = DateTime.utc(2026, 1, 1);
        await BlockCacheDao(db)
            .applySnapshotForSeason('s', [_block('b', seasonId: 's')], at);
        await EpisodeCacheDao(db)
            .applySnapshotForBlock('b', [_episode('e', blockId: 'b')], at);

        await pruneOrphanedHierarchyRows(
          db,
          liveSeasonIds: const {},
          liveBlockIds: const {},
          liveEpisodeIds: const {},
        );

        expect(await BlockCacheDao(db).readBySeason('s'), isEmpty);
        expect(await EpisodeCacheDao(db).readByBlock('b'), isEmpty);
      },
    );

    test('scoped expiry reports stale rows per TTL', () async {
      final dao = BlockCacheDao(db);
      await dao.applySnapshotForSeason('s', [
        _block('b', seasonId: 's'),
      ], DateTime.utc(2026, 1, 1));
      // Fresh within the default TTL.
      expect(
        await dao.isSeasonExpired(
          's',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 1, 2)),
        ),
        isFalse,
      );
      // Expired past the TTL.
      expect(
        await dao.isSeasonExpired(
          's',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 1, 3)),
        ),
        isTrue,
      );
      // Unknown scope never reports stale.
      expect(
        await dao.isSeasonExpired(
          'nope',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 1, 3)),
        ),
        isFalse,
      );
    });
  });

  group('BlockRepository (2.2: Ok AND Err)', () {
    late CacheDatabase db;
    late FakeBlockRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = FakeBlockRepository(BreakdownApi(), BlockCacheDao(db));
    });
    tearDown(() => db.close());

    test('listBySeason Ok writes the season snapshot to the cache', () async {
      repo.nextList = Right([_block('b1'), _block('b2')]);
      final res = await repo.listBySeason('season-1');
      expect(res.isRight(), isTrue);
      final cached = await repo.readCached('season-1');
      expect((cached as Right).value.map((v) => v.id), ['b1', 'b2']);
    });

    test('listBySeason Err leaves the cache untouched', () async {
      repo.nextList = Right([_block('b1')]);
      await repo.listBySeason('season-1');
      repo.nextList = const Left(_err);
      final res = await repo.listBySeason('season-1');
      expect(res, const Left(_err));
      expect(
        ((await repo.readCached('season-1')) as Right).value.map((v) => v.id),
        ['b1'],
      );
    });

    test('snapshot-replace removes deleted rows, scoped per season', () async {
      repo.nextList = Right([
        _block('a1', seasonId: 'season-a'),
        _block('a2', seasonId: 'season-a'),
      ]);
      await repo.listBySeason('season-a');
      repo.nextList = Right([_block('x1', seasonId: 'season-x')]);
      await repo.listBySeason('season-x');
      // Server drops a2 → deleted for season-a only; season-x untouched.
      repo.nextList = Right([_block('a1', seasonId: 'season-a')]);
      await repo.listBySeason('season-a');
      expect(
        ((await repo.readCached('season-a')) as Right).value.map((v) => v.id),
        ['a1'],
      );
      expect(
        ((await repo.readCached('season-x')) as Right).value.map((v) => v.id),
        ['x1'],
      );
    });

    test('create Ok AND Err branches', () async {
      repo.nextCreate = Right(_ack('n1'));
      expect(
        (await repo.create(
          CreateBlockRequest(
            (b) => b
              ..seriesId = 'series-1'
              ..seasonId = 'season-1'
              ..number = 1,
          ),
        )).isRight(),
        isTrue,
      );
      repo.nextCreate = const Left(_err);
      final err = await repo.create(
        CreateBlockRequest(
          (b) => b
            ..seriesId = 'series-1'
            ..seasonId = 'season-1'
            ..number = 2,
        ),
      );
      expect(err, const Left(_err));
    });
  });

  group('EpisodeRepository (2.3: Ok AND Err + groupByBlock)', () {
    late CacheDatabase db;
    late FakeEpisodeRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = FakeEpisodeRepository(BreakdownApi(), EpisodeCacheDao(db));
    });
    tearDown(() => db.close());

    test(
      'listByBlock Ok writes the block snapshot; Err is cache-neutral',
      () async {
        repo.nextList = Right([_episode('e1'), _episode('e2')]);
        expect((await repo.listByBlock('block-1')).isRight(), isTrue);
        repo.nextList = const Left(_err);
        expect(await repo.listByBlock('block-1'), const Left(_err));
        expect(
          ((await repo.readCached('block-1')) as Right).value.map((v) => v.id),
          ['e1', 'e2'],
        );
      },
    );

    test('snapshot-replace removes deleted rows, scoped per block', () async {
      repo.nextList = Right([_episode('e1'), _episode('e2')]);
      await repo.listByBlock('block-1');
      repo.nextList = Right([_episode('e1')]);
      await repo.listByBlock('block-1');
      expect(
        ((await repo.readCached('block-1')) as Right).value.map((v) => v.id),
        ['e1'],
      );
    });

    test('create Ok AND Err branches', () async {
      repo.nextCreate = Right(_ack('n1'));
      expect(
        (await repo.create(
          CreateEpisodeRequest(
            (b) => b
              ..seriesId = 'series-1'
              ..blockId = 'block-1'
              ..number = 1,
          ),
        )).isRight(),
        isTrue,
      );
      repo.nextCreate = const Left(_err);
      expect(
        await repo.create(
          CreateEpisodeRequest(
            (b) => b
              ..seriesId = 'series-1'
              ..blockId = 'block-1'
              ..number = 2,
          ),
        ),
        const Left(_err),
      );
    });

    test('groupByBlock groups rows by their block_id (pure mapper)', () {
      final grouped = EpisodeRepository.groupByBlock([
        _episode('e1', blockId: 'b1'),
        _episode('e2', blockId: 'b2'),
        _episode('e3', blockId: 'b1'),
      ]);
      expect(grouped.keys.toSet(), {'b1', 'b2'});
      expect(grouped['b1']!.map((e) => e.id), ['e1', 'e3']);
      expect(grouped['b2']!.map((e) => e.id), ['e2']);
      expect(EpisodeRepository.groupByBlock(const []), isEmpty);
    });
  });

  group('SceneRepository (2.4: Ok AND Err)', () {
    late CacheDatabase db;
    late FakeSceneRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = FakeSceneRepository(BreakdownApi(), SceneCacheDao(db));
    });
    tearDown(() => db.close());

    test(
      'listByEpisode Ok writes the episode snapshot; Err is cache-neutral',
      () async {
        repo.nextList = Right([
          _scene('s1', characters: ['c1'], shootingDays: ['d1', 'd2']),
        ]);
        expect((await repo.listByEpisode('episode-1')).isRight(), isTrue);
        final cached = ((await repo.readCached(
          'episode-1',
        )) as Right<ProblemError, List<SceneView>>).value.single;
        // List columns survive the JSON round-trip unchanged.
        expect(cached.assignedCharacters.toList(), ['c1']);
        expect(cached.shootingDayIds.toList(), ['d1', 'd2']);
        expect(cached.location, 'Studio A');
        repo.nextList = const Left(_err);
        expect(await repo.listByEpisode('episode-1'), const Left(_err));
        expect(
          ((await repo.readCached('episode-1')) as Right).value.map(
            (v) => v.id,
          ),
          ['s1'],
        );
      },
    );

    test('snapshot-replace removes deleted rows, scoped per episode', () async {
      repo.nextList = Right([_scene('s1'), _scene('s2')]);
      await repo.listByEpisode('episode-1');
      repo.nextList = Right([_scene('s2')]);
      await repo.listByEpisode('episode-1');
      expect(
        ((await repo.readCached('episode-1')) as Right).value.map((v) => v.id),
        ['s2'],
      );
    });

    test('create Ok AND Err branches', () async {
      repo.nextCreate = Right(_ack('n1'));
      SceneDetails details() => SceneDetails((b) => b..isScheduleSet = false);
      expect(
        (await repo.create(
          CreateSceneRequest(
            (b) => b
              ..episodeId = 'episode-1'
              ..details.replace(details()),
          ),
        )).isRight(),
        isTrue,
      );
      repo.nextCreate = const Left(_err);
      expect(
        await repo.create(
          CreateSceneRequest(
            (b) => b
              ..episodeId = 'episode-1'
              ..details.replace(details()),
          ),
        ),
        const Left(_err),
      );
    });
  });

  group('CostumeCategoryRepository (2.5: Ok AND Err)', () {
    late CacheDatabase db;
    late FakeCostumeCategoryRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = FakeCostumeCategoryRepository(
        BreakdownApi(),
        CostumeCategoryCacheDao(db),
      );
    });
    tearDown(() => db.close());

    test('list Ok writes the season snapshot in order_key order', () async {
      repo.nextList = Right([
        _category('c2', orderKey: 'b'),
        _category('c1', orderKey: 'a'),
      ]);
      expect((await repo.list('season-1')).isRight(), isTrue);
      // Server order (ORDER BY order_key ASC) is preserved by the read.
      expect(
        ((await repo.readCached('season-1')) as Right).value.map((v) => v.id),
        ['c1', 'c2'],
      );
    });

    test('list Err leaves the cache untouched', () async {
      repo.nextList = Right([_category('c1')]);
      await repo.list('season-1');
      repo.nextList = const Left(_err);
      expect(await repo.list('season-1'), const Left(_err));
      expect(
        ((await repo.readCached('season-1')) as Right).value.map((v) => v.id),
        ['c1'],
      );
    });

    test('create Ok AND Err branches', () async {
      repo.nextCreate = Right(_ack('n1'));
      expect(
        (await repo.create(
          'season-1',
          CreateCostumeCategoryRequest(
            (b) => b
              ..seasonId = 'season-1'
              ..name = 'Hats'
              ..orderKey = '!',
          ),
        )).isRight(),
        isTrue,
      );
      repo.nextCreate = const Left(_err);
      expect(
        await repo.create(
          'season-1',
          CreateCostumeCategoryRequest(
            (b) => b
              ..seasonId = 'season-1'
              ..name = 'Hats'
              ..orderKey = '"',
          ),
        ),
        const Left(_err),
      );
    });

    test('rename Ok AND Err (409 conflict) branches', () async {
      repo.nextWrite = const Right(2);
      expect(await repo.rename('c1', 1, 'Caps'), const Right(2));
      repo.nextWrite = const Left(ProblemError(code: 'concurrency.conflict'));
      expect(
        await repo.rename('c1', 1, 'Caps'),
        const Left(ProblemError(code: 'concurrency.conflict')),
      );
    });

    test('archive Ok AND Err branches', () async {
      repo.nextWrite = const Right(2);
      expect(
        await repo.archive('c1', VersionRequest((b) => b..version = 1)),
        const Right(2),
      );
      repo.nextWrite = const Left(_err);
      expect(
        await repo.archive('c1', VersionRequest((b) => b..version = 1)),
        const Left(_err),
      );
    });
  });
}
