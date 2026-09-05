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
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _versionConflict = ProblemError(code: 'concurrency.conflict');
const _gone = ProblemError(code: 'season.not-found', status: 404);

CostumeCategoryView _category(
  String id, {
  String orderKey = '!',
  bool archived = false,
  int version = 1,
  String? name,
}) => CostumeCategoryView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = name ?? 'Cat $id'
    ..orderKey = orderKey
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
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

class _FakeCategoryRepository extends CostumeCategoryRepository {
  _FakeCategoryRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;
  int creates = 0;
  int archiveCalls = 0;
  CreateCostumeCategoryRequest? lastCreateRequest;
  ({String id, int version, String name})? lastRename;

  @override
  Future<Result<IdVersionResponse>> create(
    String seasonId,
    CreateCostumeCategoryRequest request,
  ) {
    creates++;
    lastCreateRequest = request;
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

  @override
  Future<Result<int>> update(
    String id,
    UpdateCostumeCategoryRequest request,
  ) async {
    if (request.name != null) {
      lastRename = (id: id, version: request.version, name: request.name!);
    }
    final scripted = nextWrite;
    if (scripted != null) return scripted;
    return const Right<ProblemError, int>(2);
  }

  @override
  Future<Result<int>> archive(String id, VersionRequest version) async {
    archiveCalls++;
    final scripted = nextWrite;
    if (scripted != null) return scripted;
    return const Right<ProblemError, int>(2);
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
  late _FakeCategoryRepository repo;
  late ValueNotifier<Result<List<CostumeCategoryView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<CostumeCategoryView> initialRows = const [],
    Result<List<CostumeCategoryView>>? initialFetch,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeCategoryRepository(BreakdownApi(), CostumeCategoryCacheDao(db));
    holder = ValueNotifier<Result<List<CostumeCategoryView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        costumeCategoryRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        costumeCategoriesListFetchProvider('season-1').overrideWith((
          ref,
        ) async {
          final dao = CostumeCategoryCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<CostumeCategoryView>>(err),
            (rows) async {
              // Faithful double: the server returns ORDER BY order_key
              // ASC, so the stub sorts before snapshotting + returning.
              final ordered = rows.toList()
                ..sort((a, b) => a.orderKey.compareTo(b.orderKey));
              await dao.applySnapshotForSeason(
                'season-1',
                ordered,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<CostumeCategoryView>>(ordered);
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
        child: MaterialApp(home: CostumeCategoriesScreen(season: _season())),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Row titles in list order (archived-filtered rendering included).
  List<String> rowTitles(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title! as Text).data!)
      .toList();

  group('CostumeCategoriesScreen states (6.1, semantic finders)', () {
    testWidgets('data: rows render in order_key ascending', (tester) async {
      await setupContainer(
        initialRows: [
          _category('c2', orderKey: 'b'),
          _category('c1', orderKey: 'a'),
        ],
      );
      await pumpScreen(tester);

      expect(rowTitles(tester), ['Cat c1', 'Cat c2']);
    });

    testWidgets('empty: plain-language state with create CTA', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('categories-empty')), findsOneWidget);
      expect(find.byKey(const Key('categories-empty-create')), findsOneWidget);
    });

    testWidgets('error: retry affordance, keyed on code', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);

      expect(find.byKey(const Key('categories-error')), findsOneWidget);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
    });

    testWidgets('stale: retained rows stay visible with a banner', (
      tester,
    ) async {
      await setupContainer();
      await CostumeCategoryCacheDao(db).applySnapshotForSeason('season-1', [
        _category('c1'),
      ], DateTime.utc(2026, 1, 1));
      holder.value = const Left(_networkDown);
      await pumpScreen(tester);

      expect(find.byKey(const Key('categories-stale-banner')), findsOneWidget);
      expect(find.byKey(const Key('category-c1')), findsOneWidget);
    });

    testWidgets('overlay: created row syncs, then reconciles', (tester) async {
      await setupContainer(initialRows: [_category('c1')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('category-add-fab')));
      await _pumpFrames(tester, n: 30);
      await tester.enterText(
        find.byKey(const Key('create-category-name')),
        'Hats',
      );
      await tester.tap(find.byKey(const Key('create-category-submit')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsOneWidget);

      // Drive the parked bounded pass (manual scheduler + frames).
      holder.value = Right([
        _category('c1'),
        _category('n1', orderKey: '"', name: 'Hats'),
      ]);
      for (var i = 0; i < kMaxReconcileAttempts * 4; i++) {
        scheduler.advanceAll();
        await _pumpFrames(tester, n: 2);
        if (find.byKey(const Key('category-n1')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const Key('category-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
    });

    testWidgets('404: narrative with back affordance, no stale rows', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_gone));
      await pumpScreen(tester);

      expect(find.byKey(const Key('categories-not-found')), findsOneWidget);
      expect(find.textContaining('season.not-found'), findsOneWidget);
      expect(
        find.byKey(const Key('categories-not-found-back')),
        findsOneWidget,
      );
    });
  });

  group('CostumeCategoriesScreen flows (6.4)', () {
    testWidgets(
      'archived hidden by default, toggle reveals (no dark pattern)',
      (tester) async {
        await setupContainer(
          initialRows: [
            _category('c1'),
            _category('c2', archived: true, name: 'Old'),
          ],
        );
        await pumpScreen(tester);

        expect(find.byKey(const Key('category-c1')), findsOneWidget);
        expect(find.byKey(const Key('category-c2')), findsNothing);

        await tester.tap(find.byKey(const Key('categories-archived-toggle')));
        await _pumpFrames(tester);

        expect(find.byKey(const Key('category-c2')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('category-c2')),
            matching: find.text('Archived'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('create derives the key from the complete projection', (
      tester,
    ) async {
      // '"'-keyed row is archived (hidden) but counts for derivation.
      await setupContainer(
        initialRows: [
          _category('c1', orderKey: '!'),
          _category('c2', orderKey: '"', archived: true),
        ],
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('category-add-fab')));
      await _pumpFrames(tester, n: 30);
      await tester.enterText(
        find.byKey(const Key('create-category-name')),
        'Hats',
      );
      await tester.tap(find.byKey(const Key('create-category-submit')));
      await _pumpFrames(tester);

      expect(repo.lastCreateRequest?.orderKey, '#');
      expect(repo.lastCreateRequest?.seasonId, 'season-1');
    });

    testWidgets('rename echoes the read row version', (tester) async {
      await setupContainer(initialRows: [_category('c1', version: 4)]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('category-rename-c1')));
      await _pumpFrames(tester, n: 30);
      await tester.enterText(
        find.byKey(const Key('rename-category-name')),
        'Caps',
      );
      await tester.tap(find.byKey(const Key('rename-category-submit')));
      await _pumpFrames(tester);

      expect(repo.lastRename, (id: 'c1', version: 4, name: 'Caps'));
    });

    testWidgets('rename 409 surfaces keyed copy, no silent overwrite', (
      tester,
    ) async {
      await setupContainer(initialRows: [_category('c1', version: 4)]);
      repo.nextWrite = const Left(_versionConflict);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('category-rename-c1')));
      await _pumpFrames(tester, n: 30);
      await tester.enterText(
        find.byKey(const Key('rename-category-name')),
        'Caps',
      );
      await tester.tap(find.byKey(const Key('rename-category-submit')));
      await _pumpFrames(tester);

      expect(
        find.byKey(const Key('category-command-error-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Changed elsewhere'), findsOneWidget);
    });

    testWidgets('archive flow hides the row until the toggle reveals it', (
      tester,
    ) async {
      await setupContainer(initialRows: [_category('c1')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('category-archive-c1')));
      // Settle the dialog entrance (static dialog, no spinners): tapping
      // mid-animation misses the confirm button.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archive-category-confirm')));
      await tester.pump();
      expect(repo.archiveCalls, 1, reason: 'confirm dispatches archive');
      holder.value = Right([_category('c1', archived: true)]);
      // Awaited (not fire-and-forget): the confirm-triggered refresh may
      // refetch before the holder assignment above otherwise.
      await container
          .read(costumeCategoriesControllerProvider('season-1').notifier)
          .refresh();
      await _pumpFrames(tester, n: 10);

      expect(find.byKey(const Key('category-c1')), findsNothing);

      await tester.tap(find.byKey(const Key('categories-archived-toggle')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('category-c1')), findsOneWidget);
    });
  });

  group('CostumeCategoriesScreen goldens (6.2, data state)', () {
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
              home: CostumeCategoriesScreen(season: _season()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(CostumeCategoriesScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(initialRows: [_category('c1')]);
      await pumpGolden(
        tester,
        golden: 'costume_categories_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(initialRows: [_category('c1')]);
      await pumpGolden(
        tester,
        golden: 'costume_categories_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(initialRows: [_category('c1')]);
      await pumpGolden(
        tester,
        golden: 'costume_categories_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(initialRows: [_category('c1')]);
      await pumpGolden(
        tester,
        golden: 'costume_categories_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
