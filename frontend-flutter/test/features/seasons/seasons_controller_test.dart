// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_state.dart';

import 'seasons_test_fakes.dart';

const _networkDown = ProblemError(
  code: 'transport.connectionError',
  detail: 'server-side text',
);
const _conflict = ProblemError(code: 'seasons.conflict', status: 409);
const _listUnavailable = ProblemError(
  code: 'transport.seasons_list_unavailable',
);

/// Container wired to: in-memory Drift, fake create, holder-backed list fetch
/// (which writes Drift on Right and leaves it untouched on Left — exactly the
/// `add-drift-read-cache` contract under test), controllable scheduler,
/// dev-auth session.
_Fixture _buildFixture({List<SeasonView>? initialRows}) {
  final db = CacheDatabase(NativeDatabase.memory());
  final repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
  final holder = ValueNotifier<Result<List<SeasonView>>>(
    initialRows == null ? const Left(_listUnavailable) : Right(initialRows),
  );
  final scheduler = ManualReconciliationScheduler();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      seasonRepositoryProvider.overrideWithValue(repo),
      reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
      seasonsListFetchProvider.overrideWith((ref) async {
        final r = ref.watch(seasonRepositoryProvider);
        return r.fetchAndCacheList(() async => holder.value);
      }),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return _Fixture(container, db, repo, holder, scheduler);
}

class _Fixture {
  _Fixture(this.container, this.db, this.repo, this.holder, this.scheduler);
  final ProviderContainer container;
  final CacheDatabase db;
  final FakeSeasonRepository repo;
  final ValueNotifier<Result<List<SeasonView>>> holder;
  final ManualReconciliationScheduler scheduler;

  SeasonsController get controller =>
      container.read(seasonsControllerProvider.notifier);

  SeasonsScreenState get state => container.read(seasonsControllerProvider);
}

Future<List<String>> cachedIds(CacheDatabase db) async =>
    (await SeasonCacheDao(db).readAll()).map((s) => s.id).toList();

/// Drives the manual scheduler until [pass] completes (bounded, no
/// wall-clock gating — AGENTS.md §6 deterministic tests).
Future<void> drain(Future<void> pass, ManualReconciliationScheduler s) async {
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

  group('SeasonsController.create (D1: ack-gated optimistic insert)', () {
    test(
      'Right after 2xx inserts a controller-state overlay, never Drift',
      () async {
        final ctx = _buildFixture();

        final res = await ctx.controller.create(
          seriesId: 'series-1',
          number: 2,
          title: 'Season Two',
        );

        expect(res.isRight(), isTrue);
        final overlay = ctx.state.overlays.singleWhere((o) => o.id == 'n1');
        expect(overlay.name, 'Season Two');
        expect(overlay.number, 2);
        expect(
          overlay.status,
          anyOf(OverlayStatus.acknowledged, OverlayStatus.reconciling),
        );
        // Drift must NOT contain the unprojected row (cache invariant).
        expect(await cachedIds(ctx.db), isEmpty);
      },
    );

    test(
      'reconciliation drops the overlay when the projection carries the id',
      () async {
        final ctx = _buildFixture();
        // The projection already contains the new season, so the bounded pass
        // reconciles on its first attempt.
        ctx.holder.value = Right([
          season('n1', number: 2, title: 'Season Two'),
        ]);

        final res = await ctx.controller.create(
          seriesId: 'series-1',
          number: 2,
          title: 'Season Two',
        );
        expect(res.isRight(), isTrue);
        await ctx.controller.reconcile();

        expect(ctx.state.overlays, isEmpty);
        final ids = ctx.state.rows
            .map(
              (r) => switch (r) {
                ProjectedSeasonRow(:final season) => season.id,
                OptimisticSeasonRow(:final overlay) => overlay.id,
              },
            )
            .toList();
        expect(ids, contains('n1'));
        // Reconciled: the row is now authoritative (projected) → it lives in
        // Drift, and only there.
        expect(await cachedIds(ctx.db), contains('n1'));
      },
    );
  });

  group('SeasonsController.create failure paths (D3)', () {
    test(
      'network/5xx before 2xx: no overlay, Drift untouched, Err keyed on code',
      () async {
        final ctx = _buildFixture();
        ctx.repo.createResult = const Left(_networkDown);

        final res = await ctx.controller.create(
          seriesId: 'series-1',
          number: 2,
          title: 'X',
        );

        expect(res.isLeft(), isTrue);
        res.fold(
          (err) => expect(err.code, 'transport.connectionError'),
          (_) => fail('expected Left'),
        );
        expect(ctx.state.overlays, isEmpty); // nothing to revert — none created
        expect(ctx.state.commandError?.code, 'transport.connectionError');
        expect(await cachedIds(ctx.db), isEmpty);
      },
    );

    test(
      '409 conflict (command-side, before 2xx): no overlay exists to revert',
      () async {
        final ctx = _buildFixture(initialRows: [season('a')]);
        // Let the initial projection settle first, then snapshot Drift: the
        // failed command must not change it afterwards.
        await ctx.controller.reconcile();
        final cachedBefore = await cachedIds(ctx.db);
        ctx.repo.createResult = const Left(_conflict);

        final res = await ctx.controller.create(
          seriesId: 'series-1',
          number: 9,
          title: 'Dup',
        );

        expect(res.isLeft(), isTrue);
        res.fold((err) {
          expect(err.code, 'seasons.conflict');
          expect(err.status, 409);
        }, (_) => fail('expected Left'));
        expect(ctx.state.overlays, isEmpty);
        expect(ctx.state.commandError?.code, 'seasons.conflict');
        // Drift untouched by the failed command.
        expect(await cachedIds(ctx.db), cachedBefore);
      },
    );

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
          .read(seasonsControllerProvider.notifier)
          .create(seriesId: 'series-1', number: 1, title: 'X');

      expect(res.isLeft(), isTrue);
      res.fold(
        (err) => expect(err.code, 'authz.denied'),
        (_) => fail('expected Left'),
      );
    });
  });

  group('bounded-retry reconciliation (D2/D3)', () {
    test(
      'retry exhaustion retains the overlay marked stale + warning',
      () async {
        final ctx = _buildFixture(); // holder Left → every refetch fails
        await ctx.controller.create(
          seriesId: 'series-1',
          number: 2,
          title: 'Later',
        );

        final pass = ctx.controller.reconcile(); // joins the in-flight pass
        await drain(pass, ctx.scheduler);

        final overlay = ctx.state.overlays.single;
        expect(overlay.id, 'n1');
        expect(overlay.status, OverlayStatus.stale);
        expect(overlay.warning, kReconcileStaleWarning);
        // Drift still holds no unprojected row.
        expect(await cachedIds(ctx.db), isEmpty);
        // The budget was bounded: attempts 1..3 each requested one tick.
        expect(ctx.scheduler.ticks, kMaxReconcileAttempts - 1);
      },
    );

    test(
      'pull-to-refresh gives a stale overlay a fresh bounded pass',
      () async {
        final ctx = _buildFixture();
        await ctx.controller.create(
          seriesId: 'series-1',
          number: 2,
          title: 'Later',
        );
        await drain(ctx.controller.reconcile(), ctx.scheduler);
        expect(ctx.state.overlays.single.status, OverlayStatus.stale);

        // Projection finally catches up; refresh reconciles and drops it.
        ctx.holder.value = Right([season('n1', number: 2, title: 'Later')]);
        await ctx.controller.refresh();

        expect(ctx.state.overlays, isEmpty);
        expect(ctx.state.cachedRows.map((s) => s.id), contains('n1'));
        expect(await cachedIds(ctx.db), contains('n1'));
      },
    );

    test('reconcile with no overlays is a plain projection refresh', () async {
      final ctx = _buildFixture();
      ctx.holder.value = Right([season('a')]);

      await ctx.controller.refresh();

      expect(ctx.state.cachedRows, hasLength(1));
      expect(ctx.scheduler.ticks, 0);
    });
  });
}
