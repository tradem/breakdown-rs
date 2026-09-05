// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:frontend_flutter/features/episodes/episodes_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
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

  Result<IdVersionResponse>? nextCreate;
  int creates = 0;

  @override
  Future<Result<IdVersionResponse>> create(CreateEpisodeRequest request) {
    creates++;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'n$creates'
            ..version = 1,
        ),
      ),
    );
  }
}

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen).
Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeEpisodeRepository repo;
  late ValueNotifier<Result<List<EpisodeView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<EpisodeView> initialRows = const [],
    Result<List<EpisodeView>>? initialFetch,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeEpisodeRepository(BreakdownApi(), EpisodeCacheDao(db));
    holder = ValueNotifier<Result<List<EpisodeView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        episodeRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        episodesListFetchProvider('block-1', 'season-1').overrideWith((
          ref,
        ) async {
          final dao = EpisodeCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<EpisodeView>>(err),
            (rows) async {
              await dao.applySnapshotForBlock(
                'block-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<EpisodeView>>(rows);
            },
          );
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
        child: MaterialApp(home: EpisodesScreen(block: _block())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EpisodesScreen states (6.1, semantic finders)', () {
    testWidgets('data: renders projected rows', (tester) async {
      await setupContainer(
        initialRows: [_episode('e1', number: 2, name: 'Pilot')],
      );
      await pumpScreen(tester);

      expect(find.text('Pilot'), findsOneWidget);
      expect(find.byKey(const Key('episode-e1')), findsOneWidget);
    });

    testWidgets('empty: plain-language state with create CTA', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('episodes-empty')), findsOneWidget);
      expect(find.byKey(const Key('episodes-empty-create')), findsOneWidget);
    });

    testWidgets('error: retry affordance, keyed on code', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);

      expect(find.byKey(const Key('episodes-error')), findsOneWidget);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
    });

    testWidgets('stale: retained rows stay visible with a banner', (
      tester,
    ) async {
      await setupContainer();
      await EpisodeCacheDao(db).applySnapshotForBlock('block-1', [
        _episode('e1'),
      ], DateTime.utc(2026, 1, 1));
      holder.value = const Left(_networkDown);
      await pumpScreen(tester);

      expect(find.byKey(const Key('episodes-stale-banner')), findsOneWidget);
      expect(find.byKey(const Key('episode-e1')), findsOneWidget);
    });

    testWidgets('overlay: created row syncs, then reconciles', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('episode-add-fab')));
      // Bounded settle for the sheet entrance: the overlay spinner created
      // later would hang pumpAndSettle, and a mid-animation tap would miss.
      await _pumpFrames(tester, n: 60);
      await tester.enterText(
        find.byKey(const Key('create-episode-number')),
        '3',
      );
      await tester.enterText(
        find.byKey(const Key('create-episode-name')),
        'New Ep',
      );
      await tester.tap(find.byKey(const Key('create-episode-submit')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsOneWidget);

      // Drive the parked bounded pass (manual scheduler + frames).
      holder.value = Right([_episode('n1', number: 3, name: 'New Ep')]);
      for (var i = 0; i < kMaxReconcileAttempts * 4; i++) {
        scheduler.advanceAll();
        await _pumpFrames(tester, n: 2);
        if (find.byKey(const Key('episode-n1')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const Key('episode-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
    });

    testWidgets('404: narrative with back affordance, no stale rows', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_gone));
      await pumpScreen(tester);

      expect(find.byKey(const Key('episodes-not-found')), findsOneWidget);
      expect(find.textContaining('block.not-found'), findsOneWidget);
      expect(find.byKey(const Key('episodes-not-found-back')), findsOneWidget);
    });
  });

  group('EpisodesScreen goldens (6.2, data state)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      TargetPlatform? platform,
    }) async {
      // Reset via finally (not addTearDown): the framework verifies debug
      // variables are unset before tearDowns run.
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
              home: EpisodesScreen(block: _block()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(EpisodesScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(
        initialRows: [_episode('e1', number: 1, name: 'Pilot')],
      );
      await pumpGolden(
        tester,
        golden: 'episodes_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(
        initialRows: [_episode('e1', number: 1, name: 'Pilot')],
      );
      await pumpGolden(
        tester,
        golden: 'episodes_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(
        initialRows: [_episode('e1', number: 1, name: 'Pilot')],
      );
      await pumpGolden(
        tester,
        golden: 'episodes_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(
        initialRows: [_episode('e1', number: 1, name: 'Pilot')],
      );
      await pumpGolden(
        tester,
        golden: 'episodes_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
