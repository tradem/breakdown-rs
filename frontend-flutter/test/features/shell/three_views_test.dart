// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Widget tests for the three task-oriented view roots and the season scope
// picker (issue #610). Each view is asserted in its season-empty state and
// in a composed state driven by fake fetch seams — including the Script
// view's partial-load notice (a shortened script must never be presented
// as the season's complete one).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/features/shell/cast_tab_screen.dart';
import 'package:frontend_flutter/features/shell/schedule_tab_screen.dart';
import 'package:frontend_flutter/features/shell/script_tab_screen.dart';
import 'package:frontend_flutter/features/shell/season_scope_chip.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen).
Future<void> pumpFrames(WidgetTester tester, {int n = 10}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

SeasonView seasonDto() => SeasonView(
  (b) => b
    ..archived = false
    ..id = 'season-1'
    ..number = 1
    ..projectId = 'project-1'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView blockDto() => BlockView(
  (b) => b
    ..id = 'b-1'
    ..number = 1
    ..seasonId = 'season-1'
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView episodeDto({String? name}) => EpisodeView(
  (b) => b
    ..id = 'e-1'
    ..number = 1
    ..blockId = 'b-1'
    ..name = name
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView sceneDto(
  String id,
  int number,
  String summary, {
  String? location,
  String? scriptDay,
  List<String> characters = const [],
  List<(String, String)> beats = const [],
}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'e-1'
    ..sceneNumber = number
    ..summary = summary
    ..location = location
    ..scriptDay = scriptDay
    ..assignedCharacters.replace(characters)
    ..shootingDayIds.replace(const <String>[])
    ..isScheduleSet = false
    ..outfitBeats.replace([
      for (final (characterId, outfitId) in beats)
        SceneOutfitBeatView(
          (cb) => cb
            ..characterId = characterId
            ..outfitId = outfitId
            ..order = 0,
        ),
    ])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

ShootingDayView dayDto(String id, String orderKey, Date date) =>
    ShootingDayView(
      (b) => b
        ..id = id
        ..episodeId = 'e-1'
        ..orderKey = orderKey
        ..date = date
        ..archived = false
        ..source_.replace(
          ShootingDaySource(
            (s) => s..oneOf = OneOf.fromValue1(value: 'Manual'),
          ),
        )
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

void main() {
  late CacheDatabase db;
  late ProviderContainer container;

  Result<List<BlockView>> blocksResult = const Right([]);
  Result<List<EpisodeView>> episodesResult = const Right([]);
  Result<List<SceneView>> scenesResult = const Right([]);
  Result<List<ShootingDayView>> daysResult = const Right([]);

  Future<void> setUpContainer({bool withSeason = true}) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final seasonsHolder = ValueNotifier<Result<List<SeasonView>>>(
      Right([seasonDto()]),
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(
          FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(() async => seasonsHolder.value);
        }),
        blocksListFetchProvider('season-1')
            .overrideWith((ref) async => blocksResult),
        episodesListFetchProvider(
          'b-1',
          'season-1',
        ).overrideWith((ref) async => episodesResult),
        scenesListFetchProvider('e-1')
            .overrideWith((ref) async => scenesResult),
        shootingDaysListFetchProvider('e-1')
            .overrideWith((ref) async => daysResult),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
    if (withSeason) {
      container
          .read(shellControllerProvider.notifier)
          .setActiveSeason(seasonDto());
    }
  }

  Future<void> pumpView(WidgetTester tester, Widget view) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: view),
      ),
    );
    await pumpFrames(tester, n: 20);
  }

  group('Script view', () {
    testWidgets('without an active season: season-selection state, no error', (
      tester,
    ) async {
      await setUpContainer(withSeason: false);
      await pumpView(tester, const ScriptTabScreen());

      expect(find.byKey(const Key('script-no-season')), findsOneWidget);
      expect(find.byKey(const Key('script-list')), findsNothing);
      // The CTA opens the one surface that can SET the season.
      await tester.tap(find.byKey(const Key('view-pick-season-cta')));
      await pumpFrames(tester, n: 30);
      expect(find.byKey(const Key('season-scope-list')), findsOneWidget);
    });

    testWidgets('renders the season scenes in scene_number order', (
      tester,
    ) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      scenesResult = Right([
        sceneDto('s-2', 2, 'Zweiter'),
        sceneDto('s-1', 1, 'Erster'),
      ]);
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      expect(find.byKey(const Key('script-list')), findsOneWidget);
      expect(find.text('Erster'), findsOneWidget);
      expect(find.text('Zweiter'), findsOneWidget);
      // Numbering is visible on the rows, not implied.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('scene row: episode before number, then the metadata line '
        '(issue #709)', (tester) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto(name: 'Impuls')]);
      scenesResult = Right([
        sceneDto(
          's-1',
          12,
          'Erster',
          location: 'Kneipe',
          scriptDay: '1. Spieltag',
          characters: const ['c-1', 'c-2'],
          // Three beats, two DISTINCT pieces — the same piece worn by
          // two characters counts once.
          beats: const [
            ('c-1', 'cost-1'),
            ('c-2', 'cost-1'),
            ('c-1', 'cost-2'),
          ],
        ),
      ]);
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      // Identity: the episode (named) precedes the scene number; then the
      // metadata in the issue's order: day · location · characters ·
      // pieces — absent fields would be omitted. (This harness installs
      // no localization delegates, so l10nOf falls back to English.)
      expect(
        find.text(
          'Impuls, Scene 12 · '
          'Day: 1. Spieltag · '
          'Kneipe · '
          '2 characters · '
          '2 looks',
        ),
        findsOneWidget,
      );
    });

    testWidgets('scene row: nameless episode keeps the "Episode {n}" label '
        'and zero counts render honestly (issue #709)', (tester) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      scenesResult = Right([sceneDto('s-1', 3, 'Erster')]);
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      expect(
        find.text('Episode 1, Scene 3 · 0 characters · 0 looks'),
        findsOneWidget,
      );
    });

    testWidgets('scene row title truncates a long summary to ONE line '
        '(issue #709)', (tester) async {
      final long =
          'Int. Kneipe – Nacht. Anna betritt die Bühne, das Publikum '
          'verstummt, und der Barkeeper erkennt sie erst nach einer Ewigkeit.';
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      scenesResult = Right([sceneDto('s-1', 3, long)]);
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      final title = tester.widget<Text>(find.text(long));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('scene row sets the active-episode scope (issue #624)', (
      tester,
    ) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      scenesResult = Right([sceneDto('s-1', 1, 'Erster')]);
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      await tester.tap(find.byKey(const Key('script-scene-s-1')));
      await tester.pump();
      // The pushed detail builds against bootstrap providers this harness
      // does not override; the scope is set BEFORE the push (the contract).
      while (tester.takeException() != null) {}

      final scope = container.read(activeEpisodeProvider);
      expect(scope?.seasonId, 'season-1');
      expect(scope?.blockId, 'b-1');
      expect(scope?.episodeId, 'e-1');
    });

    testWidgets('empty season: plain-language empty state', (tester) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      scenesResult = const Right([]);
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      expect(find.byKey(const Key('script-empty')), findsOneWidget);
    });

    testWidgets('a failing episode renders a partial-load notice', (
      tester,
    ) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      scenesResult = const Left(ProblemError(code: 'scenes.network'));
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      // Honest degradation: the notice names the incomplete state instead
      // of an empty "this season has no scenes" claim.
      expect(find.byKey(const Key('script-empty')), findsNothing);
      expect(find.byKey(const Key('script-partial-notice')), findsOneWidget);
    });

    testWidgets('an unreadable block list surfaces the error state', (
      tester,
    ) async {
      blocksResult = const Left(ProblemError(code: 'blocks.forbidden'));
      await setUpContainer();
      await pumpView(tester, const ScriptTabScreen());

      expect(find.byKey(const Key('script-error')), findsOneWidget);
      // Keyed on the stable problem code, never on `detail` text.
      expect(find.textContaining('blocks.forbidden'), findsOneWidget);
    });
  });

  group('Schedule/Dispo view', () {
    testWidgets('renders the season shooting days in calendar order', (
      tester,
    ) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      daysResult = Right([
        dayDto('d-2', 'b', Date(2026, 3, 2)),
        dayDto('d-1', 'a', Date(2026, 3, 1)),
      ]);
      await setUpContainer();
      await pumpView(tester, const ScheduleTabScreen());

      expect(find.byKey(const Key('schedule-list')), findsOneWidget);
      final rowKeys = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => tile.key)
          .whereType<ValueKey<String>>()
          .map((k) => k.value)
          .toList();
      expect(rowKeys, ['schedule-day-d-1', 'schedule-day-d-2']);
    });

    testWidgets('day row sets the active-episode scope (issue #624)', (
      tester,
    ) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      daysResult = Right([dayDto('d-1', 'a', Date(2026, 3, 1))]);
      await setUpContainer();
      await pumpView(tester, const ScheduleTabScreen());

      await tester.tap(find.byKey(const Key('schedule-day-d-1')));
      await tester.pump();
      // The pushed day board builds against bootstrap providers this
      // harness does not override; the scope is set BEFORE the push.
      while (tester.takeException() != null) {}

      final scope = container.read(activeEpisodeProvider);
      expect(scope?.seasonId, 'season-1');
      expect(scope?.blockId, 'b-1');
      expect(scope?.episodeId, 'e-1');
    });

    testWidgets('no planned days: plain-language empty state', (tester) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      daysResult = const Right([]);
      await setUpContainer();
      await pumpView(tester, const ScheduleTabScreen());

      expect(find.byKey(const Key('schedule-empty')), findsOneWidget);
    });

    testWidgets('a failing episode renders a partial-load notice', (
      tester,
    ) async {
      blocksResult = Right([blockDto()]);
      episodesResult = Right([episodeDto()]);
      daysResult = const Left(ProblemError(code: 'shooting_days.forbidden'));
      await setUpContainer();
      await pumpView(tester, const ScheduleTabScreen());

      expect(find.byKey(const Key('schedule-partial-notice')), findsOneWidget);
    });
  });

  group('Cast view', () {
    testWidgets('without an active season: season-selection empty state', (
      tester,
    ) async {
      await setUpContainer(withSeason: false);
      await pumpView(tester, const CastTabScreen());

      expect(find.byKey(const Key('cast-empty')), findsOneWidget);
      // The category vocabulary is only offered once a season is scoped.
      expect(find.byKey(const Key('cast-categories-action')), findsNothing);
    });

    testWidgets('with an active season: roster/piece switch + categories', (
      tester,
    ) async {
      await setUpContainer();
      await pumpView(tester, const CastTabScreen());

      expect(find.byKey(const Key('cast-surface-switch')), findsOneWidget);
      expect(find.byKey(const Key('cast-categories-action')), findsOneWidget);
      // Both halves carry a VISIBLE label (glossary rule).
      expect(find.text('Characters'), findsWidgets);
      expect(find.text('Looks'), findsWidgets);
    });
  });

  group('season scope picker', () {
    testWidgets('offers season management and production management', (
      tester,
    ) async {
      await setUpContainer();
      await pumpView(tester, const SeasonScopePickerScreen());

      expect(
        find.byKey(const Key('season-scope-manage-seasons')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('season-scope-manage-production')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('season-scope-season-season-1')),
        findsOneWidget,
      );
    });

    testWidgets('picking a season sets the active season (acted-on DTO) and '
        'pops', (tester) async {
      await setUpContainer(withSeason: false);
      // The picker is PUSHED in the app (from the season scope chip / a
      // view's season CTA) — it must pop back to the view that opened it.
      await pumpView(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-picker'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SeasonScopePickerScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-picker')));
      await pumpFrames(tester, n: 20);

      await tester.tap(find.byKey(const Key('season-scope-season-season-1')));
      await pumpFrames(tester, n: 30);

      expect(
        container.read(shellControllerProvider).activeSeason?.id,
        'season-1',
      );
      expect(find.byKey(const Key('season-scope-list')), findsNothing);
    });
  });

  group('season scope chip', () {
    testWidgets('always visible: neutral without a season, labelled with one', (
      tester,
    ) async {
      await setUpContainer(withSeason: false);
      await pumpView(
        tester,
        const Scaffold(body: SeasonScopeChip(onOpenPicker: _noopPicker)),
      );
      // Issue #638: the season pill is NEVER hidden — it is also the only
      // affordance that can SET a season. Unset renders the neutral label.
      expect(find.byKey(const Key('season-scope-chip')), findsOneWidget);
      expect(find.text('Choose season'), findsOneWidget);

      container
          .read(shellControllerProvider.notifier)
          .setActiveSeason(seasonDto());
      await pumpFrames(tester, n: 10);
      expect(find.byKey(const Key('season-scope-chip')), findsOneWidget);
      expect(find.text('Season: Season One'), findsOneWidget);
    });

    testWidgets('a tap opens the picker (injected action)', (tester) async {
      await setUpContainer();
      var opened = 0;
      await pumpView(
        tester,
        Scaffold(body: SeasonScopeChip(onOpenPicker: () => opened++)),
      );

      await tester.tap(find.byKey(const Key('season-scope-chip')));
      await pumpFrames(tester);
      expect(opened, 1);
    });
  });
}

void _noopPicker() {}
