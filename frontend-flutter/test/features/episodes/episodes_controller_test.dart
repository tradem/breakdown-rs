// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/episode_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_state.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _conflict = ProblemError(code: 'episode.conflict', status: 409);
const _gone = ProblemError(code: 'block.not-found', status: 404);

EpisodeView _episode(String id, {int number = 1, String? name}) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = 'block-1'
    ..name = name
    ..number = number
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _block() => BlockView(
  (b) => b
    ..id = 'block-1'
    ..number = 1
    ..seasonId = 'season-1'
    ..seriesId = 'series-1'
    ..startDate = '2026-01-01'
    ..endDate = '2026-01-31'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _FakeEpisodeRepository extends EpisodeRepository {
  _FakeEpisodeRepository(super.api, super.cache);

  Result<List<EpisodeView>>? nextList;
  Result<IdVersionResponse>? nextCreate;
  CreateEpisodeRequest? lastCreateRequest;

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
  Future<Result<IdVersionResponse>> create(CreateEpisodeRequest request) {
    lastCreateRequest = request;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(Right<ProblemError, IdVersionResponse>(_ack('n1')));
  }
}

IdVersionResponse _ack(String id) => IdVersionResponse(
  (b) => b
    ..id = id
    ..version = 1,
);

Future<_Fixture> _buildFixture() async {
  final db = CacheDatabase(NativeDatabase.memory());
  final repo = _FakeEpisodeRepository(BreakdownApi(), EpisodeCacheDao(db));
  final scheduler = ManualReconciliationScheduler();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      episodeRepositoryProvider.overrideWithValue(repo),
      reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  await container.read(authSessionControllerProvider.notifier).signIn();
  return _Fixture(container, db, repo, scheduler);
}

class _Fixture {
  _Fixture(this.container, this.db, this.repo, this.scheduler);
  final ProviderContainer container;
  final CacheDatabase db;
  final _FakeEpisodeRepository repo;
  final ManualReconciliationScheduler scheduler;

  EpisodesController get controller => container.read(
    episodesControllerProvider('block-1', 'season-1').notifier,
  );

  EpisodesScreenState get state =>
      container.read(episodesControllerProvider('block-1', 'season-1'));
}

Future<void> _drain(Future<void> pass, ManualReconciliationScheduler s) async {
  var done = false;
  pass.then((_) => done = true);
  for (var i = 0; i < kMaxReconcileAttempts * 4 && !done; i++) {
    s.advanceAll();
    await pumpEventQueue();
  }
  await pass;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EpisodesController.create (ack-gated optimistic insert)', () {
    test('Right after 2xx inserts an overlay, never Drift', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);

      final res = await ctx.controller.create(block: _block(), number: 3);

      expect(res.isRight(), isTrue);
      expect(ctx.state.overlays.single.id, 'n1');
      expect((await EpisodeCacheDao(ctx.db).readByBlock('block-1')), isEmpty);
    });

    test(
      'ids come from the BlockView the user acted on (CQRS boundary)',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = const Right([]);
        await ctx.controller.create(block: _block(), number: 2, name: 'Ep');
        final req = ctx.repo.lastCreateRequest;
        expect(req, isNotNull);
        expect(req!.seriesId, 'series-1');
        expect(req.blockId, 'block-1');
        expect(req.number, 2);
        expect(req.name, 'Ep');
      },
    );

    test('reconciliation drops the overlay once projected', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = Right([_episode('n1', number: 3)]);
      await ctx.controller.create(block: _block(), number: 3);
      await ctx.controller.reconcile();
      expect(ctx.state.overlays, isEmpty);
    });
  });

  group('EpisodesController failure paths', () {
    test(
      'successful fetch converges the retained snapshot, incl. empty',
      () async {
        final ctx = await _buildFixture();
        // Hold a subscription: pins the autoDispose view/fetch
        // chain so rebuilds propagate deterministically.
        final sub = ctx.container.listen(
          episodesControllerProvider('block-1', 'season-1'),
          (_, _) {},
        );
        addTearDown(sub.close);
        ctx.repo.nextList = Right([_episode('e1'), _episode('e2')]);
        await ctx.controller.refresh();
        // Drain the notify → rebuild → microtask-set chain (bounded).
        for (var i = 0; i < 10; i++) {
          await pumpEventQueue();
        }
        expect(
          ctx.container
              .read(episodesPrevRowsProvider('block-1', 'season-1'))
              .map((e) => e.id),
          ['e1', 'e2'],
        );
        ctx.repo.nextList = const Right([]);
        await ctx.controller.refresh();
        // Drain the notify → rebuild → microtask-set chain (bounded).
        for (var i = 0; i < 10; i++) {
          await pumpEventQueue();
        }
        expect(
          ctx.container.read(episodesPrevRowsProvider('block-1', 'season-1')),
          isEmpty,
        );
      },
    );

    test('409 conflict: no overlay, keyed copy code', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);
      ctx.repo.nextCreate = const Left(_conflict);
      final res = await ctx.controller.create(block: _block(), number: 9);
      expect(res.isLeft(), isTrue);
      expect(ctx.state.overlays, isEmpty);
      expect(ctx.state.commandError?.code, 'episode.conflict');
    });

    test('exhaustion retains the overlay stale', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Left(_networkDown);
      await ctx.controller.create(block: _block(), number: 2);
      await _drain(ctx.controller.reconcile(), ctx.scheduler);
      expect(ctx.state.overlays.single.status, OverlayStatus.stale);
      expect(ctx.scheduler.ticks, kMaxReconcileAttempts - 1);
    });

    test('deleted parent (404) surfaces the not-found branch', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Left(_gone);
      await ctx.controller.refresh();
      expect(ctx.state.notFound?.code, 'block.not-found');
    });
  });
}
