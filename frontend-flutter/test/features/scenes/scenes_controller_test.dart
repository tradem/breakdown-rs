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
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/scenes/scenes_state.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _gone = ProblemError(code: 'episode.not-found', status: 404);

SceneView _scene(String id) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = false
    ..summary = 'A scene'
    ..shootingDayIds.replace(const <String>[])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView _episode() => EpisodeView(
  (b) => b
    ..id = 'episode-1'
    ..blockId = 'block-1'
    ..number = 1
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _FakeSceneRepository extends SceneRepository {
  _FakeSceneRepository(super.api, super.cache);

  Result<List<SceneView>>? nextList;
  Result<IdVersionResponse>? nextCreate;
  CreateSceneRequest? lastCreateRequest;

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
  Future<Result<IdVersionResponse>> create(CreateSceneRequest request) {
    lastCreateRequest = request;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'n1'
            ..version = 1,
        ),
      ),
    );
  }
}

Future<_Fixture> _buildFixture() async {
  final db = CacheDatabase(NativeDatabase.memory());
  final repo = _FakeSceneRepository(BreakdownApi(), SceneCacheDao(db));
  final scheduler = ManualReconciliationScheduler();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      sceneRepositoryProvider.overrideWithValue(repo),
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
  final _FakeSceneRepository repo;
  final ManualReconciliationScheduler scheduler;

  ScenesController get controller =>
      container.read(scenesControllerProvider('episode-1').notifier);

  ScenesScreenState get state =>
      container.read(scenesControllerProvider('episode-1'));
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

  group('ScenesController.create (ack-gated optimistic insert)', () {
    test(
      'Right after 2xx inserts an overlay carrying the episode id',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = const Right([]);

        final res = await ctx.controller.create(
          episode: _episode(),
          details: SceneDetails((b) => b..isScheduleSet = false),
        );

        expect(res.isRight(), isTrue);
        expect(ctx.state.overlays.single.id, 'n1');
        expect(ctx.repo.lastCreateRequest?.episodeId, 'episode-1');
        expect(
          (await SceneCacheDao(ctx.db).readByEpisode('episode-1')),
          isEmpty,
        );
      },
    );

    test('reconciliation drops the overlay once projected', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = Right([_scene('n1')]);
      await ctx.controller.create(
        episode: _episode(),
        details: SceneDetails((b) => b..isScheduleSet = false),
      );
      await ctx.controller.reconcile();
      expect(ctx.state.overlays, isEmpty);
    });
  });

  group('ScenesController failure paths', () {
    test('network failure before 2xx: no overlay, Err keyed on code', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);
      ctx.repo.nextCreate = const Left(_networkDown);
      final res = await ctx.controller.create(
        episode: _episode(),
        details: SceneDetails((b) => b..isScheduleSet = false),
      );
      expect(res.isLeft(), isTrue);
      expect(ctx.state.overlays, isEmpty);
      expect(ctx.state.commandError?.code, 'transport.connectionError');
    });

    test('exhaustion retains the overlay stale', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Left(_networkDown);
      await ctx.controller.create(
        episode: _episode(),
        details: SceneDetails((b) => b..isScheduleSet = false),
      );
      await _drain(ctx.controller.reconcile(), ctx.scheduler);
      expect(ctx.state.overlays.single.status, OverlayStatus.stale);
    });

    test('deleted parent (404) surfaces the not-found branch', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Left(_gone);
      await ctx.controller.refresh();
      expect(ctx.state.notFound?.code, 'episode.not-found');
    });
  });
}
