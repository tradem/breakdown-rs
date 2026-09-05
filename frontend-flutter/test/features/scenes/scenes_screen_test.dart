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
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/scenes/scenes_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _gone = ProblemError(code: 'episode.not-found', status: 404);

SceneView _scene(String id, {String? summary}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(const ['char-1'])
    ..isScheduleSet = true
    ..location = 'Studio A'
    ..mood = 'tense'
    ..scriptDay = 'Day 1'
    ..shootingDayIds.replace(const ['day-1', 'day-2'])
    ..summary = summary ?? 'A scene $id'
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

  Result<IdVersionResponse>? nextCreate;
  int creates = 0;

  @override
  Future<Result<IdVersionResponse>> create(CreateSceneRequest request) {
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
  late _FakeSceneRepository repo;
  late ValueNotifier<Result<List<SceneView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<SceneView> initialRows = const [],
    Result<List<SceneView>>? initialFetch,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeSceneRepository(BreakdownApi(), SceneCacheDao(db));
    holder = ValueNotifier<Result<List<SceneView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        scenesListFetchProvider('episode-1').overrideWith((ref) async {
          final dao = SceneCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<SceneView>>(err),
            (rows) async {
              await dao.applySnapshotForEpisode(
                'episode-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<SceneView>>(rows);
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
        child: MaterialApp(home: ScenesScreen(episode: _episode())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ScenesScreen states (6.1, semantic finders)', () {
    testWidgets('data: renders projected rows with read-only details', (
      tester,
    ) async {
      await setupContainer(initialRows: [_scene('s1')]);
      await pumpScreen(tester);

      expect(find.byKey(const Key('scene-s1')), findsOneWidget);
      expect(find.text('A scene s1'), findsOneWidget);
      // Read-only detail data: mood, location, script day, schedule flag,
      // character / shooting-day counts.
      expect(find.textContaining('Mood: tense'), findsOneWidget);
      expect(find.textContaining('Loc: Studio A'), findsOneWidget);
      expect(find.textContaining('Day: Day 1'), findsOneWidget);
      expect(find.textContaining('Scheduled'), findsOneWidget);
      expect(find.textContaining('1 characters'), findsOneWidget);
      expect(find.textContaining('2 shooting days'), findsOneWidget);
    });

    testWidgets('empty: plain-language state with create CTA', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('scenes-empty')), findsOneWidget);
      expect(find.byKey(const Key('scenes-empty-create')), findsOneWidget);
    });

    testWidgets('error: retry affordance, keyed on code', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);

      expect(find.byKey(const Key('scenes-error')), findsOneWidget);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
    });

    testWidgets('stale: retained rows stay visible with a banner', (
      tester,
    ) async {
      await setupContainer();
      await SceneCacheDao(db).applySnapshotForEpisode('episode-1', [
        _scene('s1'),
      ], DateTime.utc(2026, 1, 1));
      holder.value = const Left(_networkDown);
      await pumpScreen(tester);

      expect(find.byKey(const Key('scenes-stale-banner')), findsOneWidget);
      expect(find.byKey(const Key('scene-s1')), findsOneWidget);
    });

    testWidgets('overlay: created row syncs, then reconciles', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('scene-add-fab')));
      // Bounded settle for the sheet entrance: the overlay spinner created
      // later would hang pumpAndSettle, and a mid-animation tap would miss.
      await _pumpFrames(tester, n: 60);
      await tester.enterText(
        find.byKey(const Key('create-scene-summary')),
        'New scene',
      );
      await tester.tap(find.byKey(const Key('create-scene-submit')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsOneWidget);

      // Drive the parked bounded pass (manual scheduler + frames).
      holder.value = Right([_scene('n1', summary: 'New scene')]);
      for (var i = 0; i < kMaxReconcileAttempts * 4; i++) {
        scheduler.advanceAll();
        await _pumpFrames(tester, n: 2);
        if (find.byKey(const Key('scene-n1')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const Key('scene-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
    });

    testWidgets('404: narrative with back affordance, no stale rows', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_gone));
      await pumpScreen(tester);

      expect(find.byKey(const Key('scenes-not-found')), findsOneWidget);
      expect(find.textContaining('episode.not-found'), findsOneWidget);
      expect(find.byKey(const Key('scenes-not-found-back')), findsOneWidget);
    });
  });

  group('ScenesScreen goldens (6.2, data state)', () {
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
              home: ScenesScreen(episode: _episode()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(ScenesScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(initialRows: [_scene('s1')]);
      await pumpGolden(
        tester,
        golden: 'scenes_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(initialRows: [_scene('s1')]);
      await pumpGolden(
        tester,
        golden: 'scenes_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(initialRows: [_scene('s1')]);
      await pumpGolden(
        tester,
        golden: 'scenes_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(initialRows: [_scene('s1')]);
      await pumpGolden(
        tester,
        golden: 'scenes_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
