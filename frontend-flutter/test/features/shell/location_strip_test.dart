// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/shell/location_strip.dart';
import 'package:frontend_flutter/features/shell/planning_location.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

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

BlockView _block(String id, {int number = 2, String seasonId = 's1'}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = seasonId
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

EpisodeView _episode(String id, {int number = 3, String? name}) => EpisodeView(
  (b) => b
    ..id = id
    ..number = number
    ..name = name
    ..blockId = 'b1'
    ..projectId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _scene(String id, {int? sceneNumber = 12, String? summary}) =>
    SceneView(
      (b) => b
        ..id = id
        ..sceneNumber = sceneNumber
        ..summary = summary
        ..episodeId = 'e1'
        ..assignedCharacters.replace(const <String>[])
        ..shootingDayIds.replace(const <String>[])
        ..isScheduleSet = false
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

void main() {
  final season = _season('s1', title: 'Sommerkomödie');
  final block = _block('b1');
  final episode = _episode('e1', name: 'Der Diebstahl');
  final scene = _scene('sc1', summary: 'Die Küche');

  // German template locale (AGENTS.md §6 goldens; copy keys asserted here).
  Future<void> pumpStrip(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('de'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('LocationStrip segments (widget, tier 2)', () {
    testWidgets('season level renders icon + visible text', (tester) async {
      await pumpStrip(
        tester,
        LocationStrip(location: PlanningLocation.season(season)),
      );
      expect(find.text('Sommerkomödie'), findsOneWidget);
      expect(find.byKey(const Key('location-segment-season')), findsOneWidget);
    });

    testWidgets('scene level renders every segment (medium, max 4)', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        SizedBox(
          // Test fonts render wide (~1em per glyph); 800dp fits all four
          // 12px segments plus separators.
          width: 800,
          child: LocationStrip(
            location: PlanningLocation.scene(season, block, episode, scene),
            maxSegments: 4,
          ),
        ),
      );
      // Visible text for ALL four levels (icon-only segments forbidden).
      expect(find.text('Sommerkomödie'), findsOneWidget);
      expect(find.text('Block 2'), findsOneWidget);
      expect(find.text('Der Diebstahl'), findsOneWidget);
      expect(find.text('Die Küche'), findsOneWidget);
    });

    testWidgets('compact overflow: leading segments dropped (max 3)', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        SizedBox(
          width: 700,
          child: LocationStrip(
            location: PlanningLocation.scene(season, block, episode, scene),
            // Compact morphology: at most three trailing segments.
            maxSegments: 3,
          ),
        ),
      );
      expect(find.text('Sommerkomödie'), findsNothing);
      expect(find.text('Block 2'), findsOneWidget);
      expect(find.text('Der Diebstahl'), findsOneWidget);
      expect(find.text('Die Küche'), findsOneWidget);
    });

    testWidgets('insufficient width collapses to the last two segments', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        SizedBox(
          // 420dp: two 12px segments fit (~351dp in the test font), three
          // do not (~512dp) — the last TWO survive.
          width: 420,
          child: LocationStrip(
            location: PlanningLocation.scene(season, block, episode, scene),
            maxSegments: 4,
          ),
        ),
      );
      // Leading segments dropped until the row fits (min one kept) — the
      // LAST segments (deepest = current screen) survive.: leading segments dropped until the
      // row fits (min one) — the LAST segments (deepest = current screen)
      // survive.
      expect(find.text('Sommerkomödie'), findsNothing);
      expect(find.text('Block 2'), findsNothing);
      expect(find.text('Der Diebstahl'), findsOneWidget);
      expect(find.text('Die Küche'), findsOneWidget);
    });

    testWidgets('semantics node announces the FULL path', (tester) async {
      await pumpStrip(
        tester,
        SizedBox(
          // Narrow box: every leading segment is dropped (min one kept).
          width: 300,
          child: LocationStrip(
            location: PlanningLocation.scene(season, block, episode, scene),
            maxSegments: 4,
          ),
        ),
      );
      final semantics = tester.getSemantics(
        find.byKey(const Key('location-strip')),
      );
      // Even in the collapsed variant the merged node reads the whole
      // chain (never a bare "…").
      expect(
        semantics.label,
        'Position: Sommerkomödie → Block 2 → Der Diebstahl → Die Küche',
      );
    });

    testWidgets('English copy keys (en catalog)', (tester) async {
      await pumpStrip(
        tester,
        LocationStrip(location: PlanningLocation.block(season, block)),
        locale: const Locale('en'),
      );
      expect(find.text('Sommerkomödie'), findsOneWidget);
      expect(find.text('Block 2'), findsOneWidget);
      final semantics = tester.getSemantics(
        find.byKey(const Key('location-strip')),
      );
      expect(semantics.label, 'Location: Sommerkomödie → Block 2');
    });
  });

  group('strip goldens (issue #548)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required PlanningLocation location,
      required ThemeMode mode,
      required double width,
    }) async {
      tester.view.physicalSize = Size(width, 120);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
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
                child: LocationStrip(location: location, maxSegments: 4),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(LocationStrip),
        matchesGoldenFile('goldens/$golden'),
      );
    }

    testWidgets('strip with scope-less location, light', (tester) async {
      await pumpGolden(
        tester,
        golden: 'location_strip_light.png',
        location: PlanningLocation.episode(season, block, episode),
        mode: ThemeMode.light,
        width: 400,
      );
    });

    testWidgets('strip with scope-less location, dark', (tester) async {
      await pumpGolden(
        tester,
        golden: 'location_strip_dark.png',
        location: PlanningLocation.episode(season, block, episode),
        mode: ThemeMode.dark,
        width: 400,
      );
    });

    testWidgets('overflow variant, light', (tester) async {
      await pumpGolden(
        tester,
        golden: 'location_strip_overflow_light.png',
        location: PlanningLocation.scene(season, block, episode, scene),
        mode: ThemeMode.light,
        width: 220,
      );
    });
  });
}
