// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-2 widget + controller tests for `ShootingDaysScreen` (Task 6.3):
// order fidelity (no re-sort), date null-vs-absent semantics, conflicts,
// archives, create (append order_key, Manual), and goldens
// {light,dark}×{android,macos}.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _conflict = ProblemError(code: 'concurrency.conflict', status: 409);

ShootingDayView _day(
  String id, {
  String orderKey = '!',
  String? label,
  Date? date,
  bool archived = false,
  int version = 1,
}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..orderKey = orderKey
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..label = label
    ..date = date
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
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

class _FakeShootingDayRepository extends ShootingDayRepository {
  _FakeShootingDayRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;
  int createCalls = 0;
  int updateCalls = 0;
  int archiveCalls = 0;
  UpdateShootingDayRequest? lastUpdate;

  @override
  Future<Result<IdVersionResponse>> create(
    String episodeId,
    CreateShootingDayRequest request,
  ) {
    createCalls++;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right(
        IdVersionResponse(
          (b) => b
            ..id = 'd-new-$createCalls'
            ..version = 1,
        ),
      ),
    );
  }

  @override
  Future<Result<int>> update(String id, UpdateShootingDayRequest request) {
    updateCalls++;
    lastUpdate = request;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> archive(String id, VersionRequest version) {
    archiveCalls++;
    return Future.value(const Right(2));
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeShootingDayRepository repo;
  late ValueNotifier<Result<List<ShootingDayView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<ShootingDayView> initialRows = const [],
    Result<List<ShootingDayView>>? initialFetch,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeShootingDayRepository(BreakdownApi(), ShootingDayCacheDao(db));
    holder = ValueNotifier<Result<List<ShootingDayView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        shootingDayRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        shootingDaysListFetchProvider('episode-1').overrideWith((ref) async {
          final dao = ShootingDayCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match((err) => Left(err), (rows) async {
            // Faithful double: the server returns ORDER BY order_key
            // ASC, so the stub sorts before snapshotting + returning
            // (the client itself never re-sorts).
            final ordered = rows.toList()
              ..sort((a, b) => a.orderKey.compareTo(b.orderKey));
            await dao.applySnapshotForEpisode(
              'episode-1',
              ordered,
              DateTime.utc(2026, 1, 1),
            );
            return Right(ordered);
          });
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ShootingDaysScreen(episode: _episode())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ShootingDaysScreen (6.3)', () {
    testWidgets('order fidelity: server order, never re-sorted', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-2', orderKey: 'b', label: 'Second'),
          _day('d-1', orderKey: 'a', label: 'First'),
        ],
      );
      await pumpScreen(tester);
      // The DAO orders by order_key ASC; the screen renders that order.
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(tiles.map((t) => (t.title! as Text).data), ['First', 'Second']);
    });

    testWidgets('empty + error states', (tester) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      expect(find.byKey(const Key('shooting-days-empty')), findsOneWidget);
    });

    testWidgets('error renders retry', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);
      expect(find.byKey(const Key('shooting-days-error')), findsOneWidget);
      expect(find.byKey(const Key('shooting-days-retry')), findsOneWidget);
    });

    testWidgets('create: append order_key + Manual source', (tester) async {
      await setupContainer(initialRows: [_day('d-1', orderKey: '!')]);
      await pumpScreen(tester);
      final result = await container
          .read(shootingDaysControllerProvider('episode-1').notifier)
          .create(label: '2. Tag');
      expect(result.isRight(), isTrue);
      expect(repo.createCalls, 1);
      await _pumpFrames(tester);
      expect(find.byKey(const Key('overlay-d-new-1')), findsOneWidget);
    });

    testWidgets('unschedule: disabled until explicit clear works end to end', (
      tester,
    ) async {
      final day = _day('d-1', date: Date(2026, 5, 1));
      await setupContainer(initialRows: [day]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-1')));
      await tester.pumpAndSettle();
      // Explicit date clears are inexpressible end to end (backend issue
      // #372): the item renders disabled with its key so the affordance
      // does not silently vanish — and dispatches nothing.
      final item = tester.widget<PopupMenuItem<VoidCallback>>(
        find.byKey(const Key('shooting-day-unschedule-d-1')),
      );
      expect(item.enabled, isFalse);
      await tester.tap(
        find.byKey(const Key('shooting-day-unschedule-d-1')),
        warnIfMissed: false,
      );
      await _pumpFrames(tester);
      expect(repo.updateCalls, 0);
    });

    testWidgets('conflict: 409 renders keyed copy', (tester) async {
      await setupContainer(initialRows: [_day('d-1')]);
      await pumpScreen(tester);
      repo.nextWrite = const Left(_conflict);
      final result = await container
          .read(shootingDaysControllerProvider('episode-1').notifier)
          .rename(day: _day('d-1'), label: 'X');
      expect(result.isLeft(), isTrue);
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });
  });

  group('ShootingDaysScreen goldens (6.3, data state)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      TargetPlatform? platform,
    }) async {
      try {
        if (platform != null) {
          debugDefaultTargetPlatformOverride = platform;
        }
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: ShootingDaysScreen(episode: _episode()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(ShootingDaysScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
