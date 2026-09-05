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
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_screen.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
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

SeasonMembershipDto _membership({
  bool hasRole = true,
  List<String>? capabilities,
}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = hasRole
    ..capabilities.replace(
      capabilities ??
          (hasRole ? const ['upload_continuity_photos'] : const <String>[]),
    ),
);

/// Repository fake: create is scriptable (the fetch path below is
/// holder-driven through the fetch-provider override, exactly like the
/// seasons screen tests).
class _FakeBlockRepository extends BlockRepository {
  _FakeBlockRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  int creates = 0;

  @override
  Future<Result<IdVersionResponse>> create(CreateBlockRequest request) {
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
  late _FakeBlockRepository repo;
  late ValueNotifier<Result<List<BlockView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<BlockView> initialRows = const [],
    Result<List<BlockView>>? initialFetch,
    SeasonMembershipDto? membership,
    List<String>? membershipCapabilities,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeBlockRepository(BreakdownApi(), BlockCacheDao(db));
    holder = ValueNotifier<Result<List<BlockView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        blockRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        blocksListFetchProvider('season-1').overrideWith((ref) async {
          final dao = BlockCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<BlockView>>(err),
            (rows) async {
              await dao.applySnapshotForSeason(
                'season-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<BlockView>>(rows);
            },
          );
        }),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(
            membership ?? _membership(capabilities: membershipCapabilities),
          ),
        ),
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
        child: MaterialApp(home: BlocksScreen(season: _season())),
      ),
    );
    // Settle the route / FAB entrance animations; the screen itself has no
    // indeterminate animation until a create is in flight.
    await tester.pumpAndSettle();
  }

  group('BlocksScreen states (6.1, semantic finders)', () {
    testWidgets('data: renders projected rows', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpScreen(tester);

      expect(find.text('Block 2'), findsOneWidget);
      expect(find.byKey(const Key('block-b1')), findsOneWidget);
    });

    testWidgets('empty: plain-language state with create CTA', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-empty')), findsOneWidget);
      expect(find.byKey(const Key('blocks-empty-create')), findsOneWidget);
    });

    testWidgets('error: retry affordance, keyed on code', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-error')), findsOneWidget);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
    });

    testWidgets('stale: retained rows stay visible with a banner', (
      tester,
    ) async {
      await setupContainer();
      // Seed last-good rows straight into Drift, then fail the fetch.
      await BlockCacheDao(db).applySnapshotForSeason('season-1', [
        _block('b1'),
      ], DateTime.utc(2026, 1, 1));
      holder.value = const Left(_networkDown);
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-stale-banner')), findsOneWidget);
      expect(find.byKey(const Key('block-b1')), findsOneWidget);
    });

    testWidgets('overlay: created row syncs, then reconciles', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('block-add-fab')));
      // Bounded settle for the sheet entrance (600ms fake time): the
      // overlay spinner created later would hang pumpAndSettle, and a
      // mid-animation tap would miss the button.
      await _pumpFrames(tester, n: 60);
      await tester.enterText(find.byKey(const Key('create-block-number')), '4');
      await tester.tap(find.byKey(const Key('create-block-submit')));
      await _pumpFrames(tester);

      // Optimistic overlay with progress affordance (no frozen frames).
      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsOneWidget);

      // Projection catches up → drive the parked bounded pass (manual
      // scheduler + frames, seasons pattern): the create-time pass parked
      // on a backoff tick, so a bare `refresh()` would join it and wait
      // forever without `advanceAll`.
      holder.value = Right([_block('n1', number: 4)]);
      for (var i = 0; i < kMaxReconcileAttempts * 4; i++) {
        scheduler.advanceAll();
        await _pumpFrames(tester, n: 2);
        if (find.byKey(const Key('block-n1')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const Key('block-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
    });

    testWidgets('non-existent calendar date is rejected by validation', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('block-add-fab')));
      await _pumpFrames(tester, n: 60);
      await tester.enterText(find.byKey(const Key('create-block-number')), '2');
      await tester.enterText(
        find.byKey(const Key('create-block-start')),
        '2026-02-31',
      );
      await tester.tap(find.byKey(const Key('create-block-submit')));
      await _pumpFrames(tester);

      expect(find.text('Use YYYY-MM-DD'), findsOneWidget);
      expect(repo.creates, 0);
    });

    testWidgets('404: narrative with back affordance, no stale rows', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_gone));
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-not-found')), findsOneWidget);
      expect(find.textContaining('season.not-found'), findsOneWidget);
      expect(find.byKey(const Key('blocks-not-found-back')), findsOneWidget);
    });
  });

  group('membership chip (6.3, D6 display-only)', () {
    testWidgets('renders capabilities when the role is active', (tester) async {
      await setupContainer(initialRows: [_block('b1')]);
      await pumpScreen(tester);

      expect(find.byKey(const Key('membership-chip')), findsOneWidget);
      expect(find.text('upload_continuity_photos'), findsOneWidget);
    });

    testWidgets('renders the explicit no-role chip otherwise', (tester) async {
      await setupContainer(
        initialRows: [_block('b1')],
        membership: _membership(hasRole: false),
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('membership-chip-none')), findsOneWidget);
      expect(find.text('No role in this season'), findsOneWidget);
    });
  });

  group('hierarchy navigation spine (5.1, D1)', () {
    /// Container serving the seasons list AND the pushed child screens:
    /// holder-driven seasons projection plus trivial child fetches.
    Future<void> setupNavContainer() async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final seasonRepo = FakeSeasonRepository(
        BreakdownApi(),
        SeasonCacheDao(db),
      );
      repo = _FakeBlockRepository(BreakdownApi(), BlockCacheDao(db));
      final seasonsHolder = ValueNotifier<Result<List<SeasonView>>>(
        Right([_season()]),
      );
      scheduler = ManualReconciliationScheduler();
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(seasonRepo),
          blockRepositoryProvider.overrideWithValue(repo),
          costumeCategoryRepositoryProvider.overrideWithValue(
            CostumeCategoryRepository(
              BreakdownApi(),
              CostumeCategoryCacheDao(db),
            ),
          ),
          reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
          seasonsListFetchProvider.overrideWith((ref) async {
            final r = ref.watch(seasonRepositoryProvider);
            return r.fetchAndCacheList(() async => seasonsHolder.value);
          }),
          blocksListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
          costumeCategoriesListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
          membershipFetchProvider('season-1').overrideWith(
            (ref) async =>
                Right<ProblemError, SeasonMembershipDto>(_membership()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
    }

    Future<void> pumpSeasons(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SeasonsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tap season row pushes BlocksScreen; back pops', (
      tester,
    ) async {
      await setupNavContainer();
      await pumpSeasons(tester);
      expect(find.byKey(const Key('season-season-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('season-season-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.byType(BlocksScreen), findsOneWidget);

      await tester.pageBack();
      // Pop transition must finish: the dismissed route stays findable
      // until it does (both screens are static here, so settling is safe).
      await tester.pumpAndSettle();
      expect(find.byType(SeasonsScreen), findsOneWidget);
      expect(find.byType(BlocksScreen), findsNothing);
    });

    testWidgets('categories icon pushes CostumeCategoriesScreen', (
      tester,
    ) async {
      await setupNavContainer();
      await pumpSeasons(tester);

      await tester.tap(find.byKey(const Key('season-categories-season-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.byType(CostumeCategoriesScreen), findsOneWidget);
    });
  });

  group('membership strict-parse error state (6.3)', () {
    testWidgets(
      'unknown capability surfaces the error chip, never a guessed policy',
      (tester) async {
        await setupContainer(
          initialRows: [_block('b1')],
          membershipCapabilities: const ['future_cap'],
        );
        await pumpScreen(tester);

        expect(find.byKey(const Key('membership-chip-error')), findsOneWidget);
        expect(
          find.textContaining('authz.membership.capability_unknown'),
          findsOneWidget,
        );
      },
    );
  });

  group('BlocksScreen goldens (6.2, data state)', () {
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
              home: BlocksScreen(season: _season()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(BlocksScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
