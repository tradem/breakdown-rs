// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Widget tests for the fundus surface (issue #625, tasks §6.1): the season
// chip facet model, the name prefilter, repertoire season names, the deep
// link push contract, and the surface states (initial / zero-match / error /
// no-season). The cache composition itself is covered by the data-layer
// test (fundus_cache_dao_test.dart) and the pure matcher by
// fundus_model_test.dart.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/fundus_repository.dart';
import 'package:frontend_flutter/features/costumes/costume_detail_screen.dart';
import 'package:frontend_flutter/features/fundus/fundus_controller.dart';
import 'package:frontend_flutter/features/fundus/fundus_destinations.dart';
import 'package:frontend_flutter/features/fundus/fundus_model.dart';
import 'package:frontend_flutter/features/fundus/fundus_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';

const projectId = 'project-1';
const activeSeasonId = 'season-1';

Future<void> pumpFrames(WidgetTester tester, {int n = 10}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late ProviderContainer container;

  SeasonView season({
    String id = activeSeasonId,
    int number = 1,
    String? title,
  }) => SeasonView(
    (b) => b
      ..archived = false
      ..id = id
      ..number = number
      ..projectId = projectId
      ..title = title
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  );

  CostumeView costume({
    required String id,
    required List<String> repertoire,
    String notes = '',
    String? categoryName,
  }) => CostumeView(
    (b) => b
      ..id = id
      ..notes = notes
      ..categoryName = categoryName
      ..details.replace(BuiltList<CostumeDetailView>())
      ..photos.replace(BuiltList<CostumePhotoView>())
      ..seasonIds.replace(BuiltList<String>(repertoire))
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  );

  final projectSeasons = [
    season(id: activeSeasonId, number: 1, title: 'Staffel Eins'),
    season(id: 'season-2', number: 2, title: 'Staffel Zwei'),
  ];

  FundusInputs inputs({
    required List<CostumeView> costumes,
    bool stale = false,
  }) => FundusInputs(
    projectId: projectId,
    costumes: costumes,
    seasons: projectSeasons,
    stale: stale,
  );

  void setUpContainer({
    SeasonView? activeSeason,
    Result<FundusInputs>? inputsResult,
    bool markLoaded = true,
  }) {
    final db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        shellControllerProvider.overrideWith(
          () => _FixedShellController(activeSeason),
        ),
        fundusRepositoryProvider.overrideWithValue(
          _FakeFundusRepository(FundusCostumeCacheDao(db)),
        ),
        if (inputsResult != null)
          fundusInputsProvider(projectId)
              .overrideWith((ref) async => inputsResult),
      ],
    );
    addTearDown(container.dispose);
    if (markLoaded && activeSeason != null) {
      container.read(fundusLoadedProvider(projectId).notifier).markLoaded();
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FundusScreen()),
      ),
    );
    await pumpFrames(tester, n: 10);
  }

  testWidgets('season chips render and narrow the fundus', (tester) async {
    setUpContainer(
      activeSeason: season(),
      inputsResult: Right(
        inputs(
          costumes: [
            costume(id: 'k1', repertoire: [activeSeasonId], notes: 'Jacke'),
            costume(id: 'k2', repertoire: ['season-2'], notes: 'Kleid'),
          ],
        ),
      ),
    );
    await pumpScreen(tester);

    // Whole fundus by default: both rows, no chip selected.
    expect(find.byKey(const Key('fundus-row-k1')), findsOneWidget);
    expect(find.byKey(const Key('fundus-row-k2')), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const Key('fundus-season-chip-season-2')),
          )
          .selected,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('fundus-season-chip-season-2')));
    await pumpFrames(tester, n: 5);

    expect(find.byKey(const Key('fundus-row-k1')), findsNothing);
    expect(find.byKey(const Key('fundus-row-k2')), findsOneWidget);
  });

  testWidgets('name prefilter matches notes', (tester) async {
    setUpContainer(
      activeSeason: season(),
      inputsResult: Right(
        inputs(
          costumes: [
            costume(
              id: 'k1',
              repertoire: [activeSeasonId],
              notes: 'Lederjacke',
            ),
            costume(
              id: 'k2',
              repertoire: [activeSeasonId],
              notes: 'Abendkleid',
            ),
          ],
        ),
      ),
    );
    await pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('fundus-field')), 'leder');
    await pumpFrames(tester, n: 5);
    expect(find.byKey(const Key('fundus-row-k1')), findsOneWidget);
    expect(find.byKey(const Key('fundus-row-k2')), findsNothing);
  });

  testWidgets('row shows the repertoire season names', (tester) async {
    setUpContainer(
      activeSeason: season(),
      inputsResult: Right(
        inputs(
          costumes: [
            costume(
              id: 'k1',
              repertoire: [activeSeasonId, 'season-2'],
              notes: 'Jacke',
            ),
          ],
        ),
      ),
    );
    await pumpScreen(tester);
    expect(find.textContaining('Staffel Eins · Staffel Zwei'), findsOneWidget);
  });

  test(
    'deep-link contract: a cross-season costume scopes to a repertoire season',
    () {
      final active = season();
      final crossSeason = costume(id: 'k1', repertoire: ['season-2']);
      final detailSeason = fundusDetailSeason(
        costume: crossSeason,
        activeSeason: active,
        projectSeasons: projectSeasons,
      );
      expect(detailSeason?.id, 'season-2');

      // The active season wins when it is in the repertoire.
      final inActive = costume(
        id: 'k2',
        repertoire: [activeSeasonId, 'season-2'],
      );
      expect(
        fundusDetailSeason(
          costume: inActive,
          activeSeason: active,
          projectSeasons: projectSeasons,
        )?.id,
        activeSeasonId,
      );

      // The destination is the existing costume detail screen.
      expect(
        fundusDestinationScreen(
          detailSeason: detailSeason!,
          costume: crossSeason,
        ),
        isA<CostumeDetailScreen>(),
      );
    },
  );

  testWidgets('zero-match echoes the query', (tester) async {
    setUpContainer(
      activeSeason: season(),
      inputsResult: Right(
        inputs(
          costumes: [
            costume(id: 'k1', repertoire: [activeSeasonId], notes: 'Jacke'),
          ],
        ),
      ),
    );
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const Key('fundus-field')), 'xyz');
    await pumpFrames(tester, n: 5);
    final text = tester
        .widget<Text>(find.byKey(const Key('fundus-zero-match')))
        .data!;
    expect(text, contains('xyz'));
  });

  testWidgets('storage failure surfaces the error state with retry', (
    tester,
  ) async {
    setUpContainer(
      activeSeason: season(),
      inputsResult: const Left(ProblemError(code: 'cache.read_failed')),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('fundus-error')), findsOneWidget);
    expect(find.byKey(const Key('view-retry')), findsOneWidget);
  });

  testWidgets('no active season: empty state, no results computed', (
    tester,
  ) async {
    setUpContainer(activeSeason: null, markLoaded: false);
    await pumpScreen(tester);
    expect(find.byKey(const Key('fundus-no-season')), findsOneWidget);
    expect(find.byKey(const Key('fundus-field')), findsNothing);
  });

  testWidgets('golden: fundus data state (light)', (tester) async {
    setUpContainer(
      activeSeason: season(),
      inputsResult: Right(
        inputs(
          costumes: [
            costume(
              id: 'k1',
              repertoire: [activeSeasonId, 'season-2'],
              notes: 'Rote Lederjacke',
              categoryName: 'Accessoires',
            ),
            costume(
              id: 'k2',
              repertoire: [activeSeasonId],
              notes: 'Abendkleid',
            ),
          ],
        ),
      ),
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: const FundusScreen(),
        ),
      ),
    );
    await pumpFrames(tester, n: 10);
    await expectLater(
      find.byType(FundusScreen),
      matchesGoldenFile('goldens/fundus_screen_light.png'),
    );
  });
}

class _FixedShellController extends ShellController {
  _FixedShellController(this._season);

  final SeasonView? _season;

  @override
  ShellState build() => ShellState(selectedIndex: 0, activeSeason: _season);
}

class _FakeFundusRepository extends FundusRepository {
  _FakeFundusRepository(FundusCostumeCacheDao cache)
    : super(BreakdownApi(), cache);

  @override
  Future<Result<List<CostumeView>>> listByProject(
    String projectId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => const Right([]);
}
