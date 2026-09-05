// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/data/episode_repository.dart';
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_screen.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_screen.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/scenes/scenes_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-e2e'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _block(String id) => BlockView(
  (b) => b
    ..id = id
    ..number = 1
    ..seasonId = 'season-1'
    ..seriesId = 'series-e2e'
    ..startDate = '2026-01-01'
    ..endDate = '2026-01-31'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView _episode(String id) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = 'block-1'
    ..number = 1
    ..seriesId = 'series-e2e'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _scene(String id) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = false
    ..summary = 'Scene'
    ..shootingDayIds.replace(const <String>[])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

CostumeCategoryView _category(String id, String orderKey) =>
    CostumeCategoryView(
      (b) => b
        ..id = id
        ..seasonId = 'season-1'
        ..name = 'Cat $id'
        ..orderKey = orderKey
        ..archived = false
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

/// Scriptable create for the category step (the fetch path stays
/// holder-driven like every other level).
class _FakeCategoryRepository extends CostumeCategoryRepository {
  _FakeCategoryRepository(super.api, super.cache);

  int creates = 0;

  @override
  Future<Result<IdVersionResponse>> create(
    String seasonId,
    CreateCostumeCategoryRequest request,
  ) {
    creates++;
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'cat-$creates'
            ..version = 1,
        ),
      ),
    );
  }
}

SeasonMembershipDto _membership() => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(const ['upload_continuity_photos']),
);

/// Immediate scheduler so no backoff is ever awaited on-device
/// (deterministic reconciliation without wall-clock gating, AGENTS.md §6).
class _E2eScheduler extends ReconciliationScheduler {
  const _E2eScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const devConfig = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.2.2:3000',
    oidcIss: '',
    devAuthSub: 'dev-e2e',
    oidcAudience: '',
    oidcClientId: '',
    oidcRedirectUri: '',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
    defaultSeriesId: 'series-e2e',
  );

  testWidgets(
    'Hierarchy spine: season → block → episode → scene → category, back preserves state',
    (tester) async {
      final db = CacheDatabase();
      addTearDown(db.close);

      final seasonsHolder = ValueNotifier<Result<List<SeasonView>>>(
        Right([_season()]),
      );
      final blocksHolder = ValueNotifier<Result<List<BlockView>>>(
        Right([_block('block-1')]),
      );
      final episodesHolder = ValueNotifier<Result<List<EpisodeView>>>(
        Right([_episode('episode-1')]),
      );
      final scenesHolder = ValueNotifier<Result<List<SceneView>>>(
        Right([_scene('scene-1')]),
      );
      final categoriesHolder = ValueNotifier<Result<List<CostumeCategoryView>>>(
        const Right([]),
      );

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(
            SeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
          ),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _E2eScheduler(),
          ),
          seasonsListFetchProvider.overrideWith((ref) async {
            final dao = SeasonCacheDao(ref.watch(cacheDatabaseProvider));
            return seasonsHolder.value.match(
              (err) => Left<ProblemError, List<SeasonView>>(err),
              (rows) async {
                await dao.applySnapshot(rows, DateTime.utc(2026, 1, 1));
                return Right<ProblemError, List<SeasonView>>(rows);
              },
            );
          }),
          blocksListFetchProvider('season-1').overrideWith((ref) async {
            final dao = BlockCacheDao(ref.watch(cacheDatabaseProvider));
            return blocksHolder.value.match(
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
          episodesListFetchProvider(
            'block-1',
            'season-1',
          ).overrideWith((ref) async => episodesHolder.value),
          scenesListFetchProvider('episode-1')
              .overrideWith((ref) async => scenesHolder.value),
          costumeCategoriesListFetchProvider('season-1')
              .overrideWith((ref) async => categoriesHolder.value),
          membershipFetchProvider('season-1').overrideWith(
            (ref) async =>
                Right<ProblemError, SeasonMembershipDto>(_membership()),
          ),
          blockRepositoryProvider.overrideWithValue(
            BlockRepository(BreakdownApi(), BlockCacheDao(db)),
          ),
          episodeRepositoryProvider.overrideWithValue(
            EpisodeRepository(BreakdownApi(), EpisodeCacheDao(db)),
          ),
          sceneRepositoryProvider.overrideWithValue(
            SceneRepository(BreakdownApi(), SceneCacheDao(db)),
          ),
          costumeCategoryRepositoryProvider.overrideWithValue(
            _FakeCategoryRepository(
              BreakdownApi(),
              CostumeCategoryCacheDao(db),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SeasonsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Season → blocks.
      await tester.tap(find.byKey(const Key('season-season-1')));
      await tester.pumpAndSettle();
      expect(find.byType(BlocksScreen), findsOneWidget);
      expect(find.byKey(const Key('block-block-1')), findsOneWidget);

      // Block → episodes (server-side ?block_id= filter, D3).
      await tester.tap(find.byKey(const Key('block-block-1')));
      await tester.pumpAndSettle();
      expect(find.byType(EpisodesScreen), findsOneWidget);
      expect(find.byKey(const Key('episode-episode-1')), findsOneWidget);

      // Episode → scenes.
      await tester.tap(find.byKey(const Key('episode-episode-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ScenesScreen), findsOneWidget);
      expect(find.byKey(const Key('scene-scene-1')), findsOneWidget);

      // Back navigation preserves parent state (no re-fetch storm).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EpisodesScreen), findsOneWidget);
      expect(find.byKey(const Key('episode-episode-1')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BlocksScreen), findsOneWidget);
      expect(find.byKey(const Key('block-block-1')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SeasonsScreen), findsOneWidget);

      // Categories from the season context; create appends '!' (empty vocab).
      await tester.tap(find.byKey(const Key('season-categories-season-1')));
      await tester.pumpAndSettle();
      expect(find.byType(CostumeCategoriesScreen), findsOneWidget);
      expect(find.byKey(const Key('categories-empty')), findsOneWidget);

      // Create the first category; the optimistic overlay reconciles once
      // the projection carries it.
      await tester.tap(find.byKey(const Key('category-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-category-name')),
        'Hats',
      );
      await tester.tap(find.byKey(const Key('create-category-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('overlay-cat-1')), findsOneWidget);

      categoriesHolder.value = Right([_category('cat-1', '!')]);
      // Fresh bounded pass after the projection caught up (the
      // create-time pass already exhausted on the empty snapshot).
      await container
          .read(costumeCategoriesControllerProvider('season-1').notifier)
          .refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-cat-1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-cat-1')), findsNothing);
    },
  );
}
