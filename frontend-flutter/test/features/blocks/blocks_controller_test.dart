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
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_state.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _conflict = ProblemError(code: 'blocks.conflict', status: 409);
const _gone = ProblemError(code: 'season.not-found', status: 404);

BlockView _block(String id, {int number = 1}) => BlockView(
  (b) => b
    ..id = id
    ..number = number
    ..seasonId = 'season-1'
    ..seriesId = 'series-1'
    ..startDate = '2026-01-01'
    ..endDate = '2026-01-31'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-1'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _FakeBlockRepository extends BlockRepository {
  _FakeBlockRepository(super.api, super.cache);

  Result<List<BlockView>>? nextList;
  Result<IdVersionResponse>? nextCreate;
  int createCalls = 0;

  /// The last request that reached the "network" (payload assertions).
  CreateBlockRequest? lastCreateRequest;

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
  Future<Result<IdVersionResponse>> create(CreateBlockRequest request) {
    createCalls++;
    lastCreateRequest = request;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'n$createCalls'
            ..version = 1,
        ),
      ),
    );
  }
}

Future<_Fixture> _buildFixture() async {
  final db = CacheDatabase(NativeDatabase.memory());
  final repo = _FakeBlockRepository(BreakdownApi(), BlockCacheDao(db));
  final scheduler = ManualReconciliationScheduler();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      blockRepositoryProvider.overrideWithValue(repo),
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
  final _FakeBlockRepository repo;
  final ManualReconciliationScheduler scheduler;

  BlocksController get controller =>
      container.read(blocksControllerProvider('season-1').notifier);

  BlocksScreenState get state =>
      container.read(blocksControllerProvider('season-1'));
}

Future<List<String>> _cachedIds(CacheDatabase db) async =>
    (await BlockCacheDao(db).readBySeason('season-1'))
        .map((b) => b.id)
        .toList();

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

  group('BlocksController.create (ack-gated optimistic insert)', () {
    test(
      'Right after 2xx inserts a controller-state overlay, never Drift',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = const Right([]);

        final res = await ctx.controller.create(season: _season(), number: 2);

        expect(res.isRight(), isTrue);
        final overlay = ctx.state.overlays.singleWhere((o) => o.id == 'n1');
        expect(overlay.number, 2);
        expect(
          overlay.status,
          anyOf(OverlayStatus.acknowledged, OverlayStatus.reconciling),
        );
        expect(await _cachedIds(ctx.db), isEmpty);
      },
    );

    test(
      'reconciliation drops the overlay when the projection carries the id',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = Right([_block('n1', number: 2)]);

        expect(
          (await ctx.controller.create(season: _season(), number: 2)).isRight(),
          isTrue,
        );
        await ctx.controller.reconcile();

        expect(ctx.state.overlays, isEmpty);
        expect(await _cachedIds(ctx.db), contains('n1'));
      },
    );

    test(
      'ids come from the SeasonView the user acted on (CQRS boundary)',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = const Right([]);
        final other = SeasonView(
          (b) => b
            ..id = 'season-9'
            ..number = 9
            ..seriesId = 'series-9'
            ..updatedAt = DateTime.utc(2026, 1, 1)
            ..version = 3,
        );
        await ctx.controller.create(season: other, number: 4);
        final req = ctx.repo.lastCreateRequest;
        expect(req, isNotNull);
        expect(req!.seriesId, 'series-9');
        expect(req.seasonId, 'season-9');
        expect(req.number, 4);
      },
    );
  });

  group('BlocksController.create failure paths', () {
    test('network/5xx before 2xx: no overlay, Err keyed on code', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);
      ctx.repo.nextCreate = const Left(_networkDown);

      final res = await ctx.controller.create(season: _season(), number: 2);

      expect(res.isLeft(), isTrue);
      expect(ctx.state.overlays, isEmpty);
      expect(ctx.state.commandError?.code, 'transport.connectionError');
      expect(await _cachedIds(ctx.db), isEmpty);
    });

    test('409 conflict: no overlay, keyed copy code', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);
      ctx.repo.nextCreate = const Left(_conflict);

      final res = await ctx.controller.create(season: _season(), number: 9);

      expect(res.isLeft(), isTrue);
      expect(ctx.state.overlays, isEmpty);
      expect(ctx.state.commandError?.code, 'blocks.conflict');
    });

    test('AUTHZ-GATE: signed out → denied without any network call', () async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(realOidcConfig),
          dioProvider.overrideWithValue(Dio()),
          tokenStoreProvider.overrideWithValue(FakeTokenStore(null)),
        ],
      );
      addTearDown(container.dispose);

      final res = await container
          .read(blocksControllerProvider('season-1').notifier)
          .create(season: _season(), number: 1);

      expect(res.isLeft(), isTrue);
      res.fold(
        (err) => expect(err.code, 'authz.denied'),
        (_) => fail('expected Left'),
      );
    });
  });

  group('BlocksController reconciliation + 404', () {
    test(
      'successful fetch converges the retained snapshot, incl. empty',
      () async {
        final ctx = await _buildFixture();
        // Hold a subscription: pins the autoDispose view/fetch
        // chain so rebuilds propagate deterministically.
        final sub = ctx.container.listen(
          blocksControllerProvider('season-1'),
          (_, _) {},
        );
        addTearDown(sub.close);
        ctx.repo.nextList = Right([_block('a'), _block('b')]);
        await ctx.controller.refresh();
        // Drain the notify → rebuild → microtask-set chain (bounded).
        for (var i = 0; i < 10; i++) {
          await pumpEventQueue();
        }
        expect(
          ctx.container
              .read(blocksPrevRowsProvider('season-1'))
              .map((b) => b.id),
          ['a', 'b'],
        );
        // A successful EMPTY snapshot replaces (never resurrects deleted).
        ctx.repo.nextList = const Right([]);
        await ctx.controller.refresh();
        // Drain the notify → rebuild → microtask-set chain (bounded).
        for (var i = 0; i < 10; i++) {
          await pumpEventQueue();
        }
        expect(ctx.container.read(blocksPrevRowsProvider('season-1')), isEmpty);
      },
    );

    test(
      'retry exhaustion retains the overlay marked stale + warning',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = const Left(_networkDown);
        await ctx.controller.create(season: _season(), number: 2);

        await _drain(ctx.controller.reconcile(), ctx.scheduler);

        final overlay = ctx.state.overlays.single;
        expect(overlay.status, OverlayStatus.stale);
        expect(overlay.warning, kReconcileStaleWarning);
        expect(ctx.scheduler.ticks, kMaxReconcileAttempts - 1);
      },
    );

    test('deleted parent (404) surfaces the not-found branch', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Left(_gone);
      await ctx.controller.refresh();
      expect(ctx.state.notFound?.code, 'season.not-found');
    });
  });
}
