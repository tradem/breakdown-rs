// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/shell/active_episode_chip.dart';
import 'package:frontend_flutter/features/shell/planning_location.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../../support/fake_secure_storage.dart';

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..archived = false
    ..id = id
    ..number = number
    ..projectId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView _episode(String id, {int number = 1, String? name}) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = 'block-1'
    ..number = number
    ..name = name
    ..projectId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

void main() {
  late FakeSecureStoragePlatform platform;

  setUp(() {
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  Future<void> pumpChip(
    WidgetTester tester, {
    required ProviderContainer container,
    PlanningLocation? location,
    void Function(String seasonId, String blockId)? onOpenPicker,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ActiveEpisodeChip(
              location: location,
              onOpenPicker: onOpenPicker ?? (_, _) {},
            ),
          ),
        ),
      ),
    );
  }

  group('ActiveEpisodeChip arms (issue #624)', () {
    testWidgets('no scope → hidden', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpChip(tester, container: container);
      expect(find.byKey(const Key('active-episode-chip')), findsNothing);
    });

    testWidgets('scoped → visible with the name label', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-1',
            blockId: 'block-1',
            episodeId: 'episode-1',
            episodeNumber: 3,
            episodeName: 'Pilot',
          );
      await settle(tester);
      await pumpChip(tester, container: container);
      expect(find.byKey(const Key('active-episode-chip')), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget);
    });

    testWidgets('scoped without a name falls back to the number label', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-1',
            blockId: 'block-1',
            episodeId: 'episode-1',
            episodeNumber: 3,
          );
      await settle(tester);
      await pumpChip(tester, container: container);
      expect(find.text('Episode 3'), findsOneWidget);
    });

    testWidgets('foreign season → the chip says so', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-1',
            blockId: 'block-1',
            episodeId: 'episode-1',
            episodeNumber: 3,
            episodeName: 'Pilot',
          );
      await settle(tester);
      await pumpChip(
        tester,
        container: container,
        location: PlanningLocation.season(_season('season-2', number: 2)),
      );
      expect(
        find.text('Filter gilt hier nicht – andere Season'),
        findsOneWidget,
      );
      expect(find.text('Pilot'), findsNothing);
    });

    testWidgets('tap opens the picker for the scope season and block', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-1',
            blockId: 'block-1',
            episodeId: 'episode-1',
            episodeNumber: 1,
          );
      await settle(tester);
      String? seenSeason;
      String? seenBlock;
      await pumpChip(
        tester,
        container: container,
        onOpenPicker: (seasonId, blockId) {
          seenSeason = seasonId;
          seenBlock = blockId;
        },
      );
      await tester.tap(find.byKey(const Key('active-episode-chip')));
      await tester.pump();
      expect(seenSeason, 'season-1');
      expect(seenBlock, 'block-1');
    });
  });

  group('EpisodeScopePickerScreen (chip tap → picker → changeable scope)', () {
    testWidgets('pick sets the sticky scope and pops', (tester) async {
      final container = ProviderContainer(
        overrides: [
          episodesListFetchProvider('block-1', 'season-1').overrideWith(
            (ref) async => Right<ProblemError, List<EpisodeView>>([
              _episode('episode-1', number: 1, name: 'Pilot'),
              _episode('episode-2', number: 2),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  key: const Key('open-picker'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EpisodeScopePickerScreen(
                        seasonId: 'season-1',
                        blockId: 'block-1',
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-picker')));
      await settle(tester);

      expect(find.byKey(const Key('episode-scope-picker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('episode-scope-pick-episode-2')));
      await settle(tester);

      expect(container.read(activeEpisodeProvider), isNotNull);
      expect(container.read(activeEpisodeProvider)?.episodeId, 'episode-2');
      expect(container.read(activeEpisodeProvider)?.episodeNumber, 2);
      // Popped back to the opener.
      expect(find.byKey(const Key('open-picker')), findsOneWidget);
      expect(find.byKey(const Key('episode-scope-picker')), findsNothing);
    });

    testWidgets('pull-to-refresh refetches the shared seam and shows the '
        'created episode (issue #666 — no stale list)', (tester) async {
      // Cache-first seam: the first fetch serves the STALE list; after the
      // invalidate the fetch serves the post-apply list with the new episode.
      var fetchCount = 0;
      final container = ProviderContainer(
        overrides: [
          episodesListFetchProvider('block-1', 'season-1').overrideWith((
            ref,
          ) async {
            fetchCount++;
            if (fetchCount == 1) {
              return Right<ProblemError, List<EpisodeView>>([
                _episode('episode-1', number: 1, name: 'Pilot'),
              ]);
            }
            return Right<ProblemError, List<EpisodeView>>([
              _episode('episode-1', number: 1, name: 'Pilot'),
              _episode('episode-293', number: 293),
            ]);
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const EpisodeScopePickerScreen(
              seasonId: 'season-1',
              blockId: 'block-1',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(
        find.byKey(const Key('episode-scope-pick-episode-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('episode-scope-pick-episode-293')),
        findsNothing,
      );

      // Pull to refresh: the invalidate re-runs the fetch, which now
      // returns the post-apply rows.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('episode-scope-picker'))),
      );
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('episode-scope-pick-episode-293')),
        findsOneWidget,
      );
    });

    testWidgets('empty list → the honest empty narrative', (tester) async {
      final container = ProviderContainer(
        overrides: [
          episodesListFetchProvider('block-1', 'season-1').overrideWith(
            (ref) async => const Right<ProblemError, List<EpisodeView>>([]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const EpisodeScopePickerScreen(
              seasonId: 'season-1',
              blockId: 'block-1',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('episode-scope-empty')), findsOneWidget);
    });
  });

  group('ActiveEpisodeChip goldens (issue #624)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
    }) async {
      tester.view.physicalSize = const Size(400, 120);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-1',
            blockId: 'block-1',
            episodeId: 'episode-1',
            episodeNumber: 3,
            episodeName: 'Pilot',
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: mode,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Center(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCCCCCC)),
                  ),
                  child: ActiveEpisodeChip(onOpenPicker: (_, _) {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(ActiveEpisodeChip),
        matchesGoldenFile('goldens/$golden'),
      );
    }

    testWidgets('episode chip light', (tester) async {
      await pumpGolden(
        tester,
        golden: 'active_episode_chip_light.png',
        mode: ThemeMode.light,
      );
    });

    testWidgets('episode chip dark', (tester) async {
      await pumpGolden(
        tester,
        golden: 'active_episode_chip_dark.png',
        mode: ThemeMode.dark,
      );
    });
  });
}
