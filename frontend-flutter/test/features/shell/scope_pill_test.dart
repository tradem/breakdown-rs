// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Widget tests for the shell's scope pills (issue #638): the shared rounded
// pill styling, the prerequisite-aware visibility of the three scope levels
// and the per-level selected highlight color. The pills are pumped together
// (the way the shell's top bar renders them) so their colors are comparable.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/shell/active_episode_chip.dart';
import 'package:frontend_flutter/features/shell/active_scope_chip.dart';
import 'package:frontend_flutter/features/shell/season_scope_chip.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../../support/fake_secure_storage.dart';
import '../seasons/seasons_test_fakes.dart';

/// Drains the fire-and-forget persistence chains (deterministic frame pumps,
/// no wall clock — the same shape `active_scope_chip_test.dart` uses).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

void main() {
  late CacheDatabase db;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(db),
        blockRepositoryProvider.overrideWithValue(
          BlockRepository(BreakdownApi(), BlockCacheDao(db)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpPills(
    WidgetTester tester,
    ProviderContainer container, {
    void Function(String seasonId)? onBlock,
    void Function(String seasonId, String blockId)? onEpisode,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Wrap(
              children: [
                SeasonScopeChip(onOpenPicker: () {}),
                ActiveScopeChip(onOpenPicker: onBlock ?? (_) {}),
                ActiveEpisodeChip(onOpenPicker: onEpisode ?? (_, _) {}),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// The resolved fill of a pill.
  Color pillColor(WidgetTester tester, Key key) => tester
      .widget<ActionChip>(
        find.descendant(of: find.byKey(key), matching: find.byType(ActionChip)),
      )
      .backgroundColor!;

  void setSeason(ProviderContainer container) => container
      .read(shellControllerProvider.notifier)
      .setActiveSeason(season('season-1', number: 1, title: 'Shell Season'));

  void setBlock(ProviderContainer container) => container
      .read(activeBlockProvider.notifier)
      .set(seasonId: 'season-1', blockId: 'b-1', blockNumber: 2);

  void setEpisode(ProviderContainer container) => container
      .read(activeEpisodeProvider.notifier)
      .set(
        seasonId: 'season-1',
        blockId: 'b-1',
        episodeId: 'e-1',
        episodeNumber: 3,
        episodeName: 'Pilot',
      );

  testWidgets('prerequisite-aware visibility: season → block → episode', (
    tester,
  ) async {
    final container = makeContainer();
    await pumpPills(tester, container);

    // No season: only the season pill (the only affordance that can SET a
    // season) renders.
    expect(find.byKey(const Key('season-scope-chip')), findsOneWidget);
    expect(find.byKey(const Key('active-scope-chip')), findsNothing);
    expect(find.byKey(const Key('active-episode-chip')), findsNothing);
    expect(find.text('Season wählen'), findsOneWidget);

    // Season active: the block pill appears, neutral and actionable.
    setSeason(container);
    await settle(tester);
    expect(find.byKey(const Key('active-scope-chip')), findsOneWidget);
    expect(find.byKey(const Key('active-episode-chip')), findsNothing);
    expect(find.text('Block wählen'), findsOneWidget);
    expect(find.text('Season: Shell Season'), findsOneWidget);

    // Block scope set: the episode pill appears, neutral and actionable.
    setBlock(container);
    await settle(tester);
    expect(find.byKey(const Key('active-episode-chip')), findsOneWidget);
    expect(find.text('Episode wählen'), findsOneWidget);
    expect(find.text('Filter: Block 2'), findsOneWidget);
  });

  testWidgets('selected pills are highlighted per level', (tester) async {
    final container = makeContainer();
    await pumpPills(tester, container);

    final neutral = pillColor(tester, const Key('season-scope-chip'));

    setSeason(container);
    await settle(tester);
    final selectedSeason = pillColor(tester, const Key('season-scope-chip'));
    final neutralBlock = pillColor(tester, const Key('active-scope-chip'));
    expect(selectedSeason, isNot(neutral));
    expect(neutralBlock, neutral);

    setBlock(container);
    await settle(tester);
    final selectedBlock = pillColor(tester, const Key('active-scope-chip'));
    final neutralEpisode = pillColor(tester, const Key('active-episode-chip'));
    expect(selectedBlock, isNot(neutralBlock));
    expect(neutralEpisode, neutralBlock);

    setEpisode(container);
    await settle(tester);
    // All three levels are distinguishable by color.
    final colors = {
      pillColor(tester, const Key('season-scope-chip')),
      pillColor(tester, const Key('active-scope-chip')),
      pillColor(tester, const Key('active-episode-chip')),
    };
    expect(colors.length, 3);
  });

  testWidgets('an unset pill opens its picker for the active scope ids', (
    tester,
  ) async {
    final container = makeContainer();
    String? seenBlockSeason;
    String? seenEpisodeSeason;
    String? seenEpisodeBlock;
    await pumpPills(
      tester,
      container,
      onBlock: (seasonId) => seenBlockSeason = seasonId,
      onEpisode: (seasonId, blockId) {
        seenEpisodeSeason = seasonId;
        seenEpisodeBlock = blockId;
      },
    );

    setSeason(container);
    await settle(tester);
    await tester.tap(find.byKey(const Key('active-scope-chip')));
    await settle(tester);
    expect(seenBlockSeason, 'season-1');

    setBlock(container);
    await settle(tester);
    await tester.tap(find.byKey(const Key('active-episode-chip')));
    await settle(tester);
    expect(seenEpisodeSeason, 'season-1');
    expect(seenEpisodeBlock, 'b-1');
  });

  testWidgets('pills keep a 48dp touch target', (tester) async {
    final container = makeContainer();
    await pumpPills(tester, container);
    final size = tester.getSize(find.byKey(const Key('season-scope-chip')));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('pills are fully rounded (stadium shape)', (tester) async {
    final container = makeContainer();
    await pumpPills(tester, container);
    final chip = tester.widget<ActionChip>(
      find.descendant(
        of: find.byKey(const Key('season-scope-chip')),
        matching: find.byType(ActionChip),
      ),
    );
    expect(chip.shape, isA<StadiumBorder>());
  });

  group('scope pill goldens (issue #638)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      required bool allSelected,
    }) async {
      tester.view.physicalSize = const Size(420, 140);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = makeContainer();
      setSeason(container);
      if (allSelected) {
        setBlock(container);
        setEpisode(container);
      }
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
                  key: const Key('scope-pill-strip'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCCCCCC)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      SeasonScopeChip(onOpenPicker: () {}),
                      ActiveScopeChip(onOpenPicker: (_) {}),
                      ActiveEpisodeChip(onOpenPicker: (_, _) {}),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      // Let the chip tooltips' timers drain before the golden capture
      // (fake-async advance, no wall clock).
      await tester.pump(const Duration(seconds: 2));
      await expectLater(
        find.byKey(const Key('scope-pill-strip')),
        matchesGoldenFile('goldens/$golden'),
      );
    }

    testWidgets('all levels selected light', (tester) async {
      await pumpGolden(
        tester,
        golden: 'scope_pills_selected_light.png',
        mode: ThemeMode.light,
        allSelected: true,
      );
    });

    testWidgets('all levels selected dark', (tester) async {
      await pumpGolden(
        tester,
        golden: 'scope_pills_selected_dark.png',
        mode: ThemeMode.dark,
        allSelected: true,
      );
    });

    testWidgets('prerequisites only light', (tester) async {
      await pumpGolden(
        tester,
        golden: 'scope_pills_neutral_light.png',
        mode: ThemeMode.light,
        allSelected: false,
      );
    });
  });
}
