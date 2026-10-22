// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Tier-2 tests for the set-shorthand mood reinforcement (issue #721): the
// `BreakdownMaterialIcons.forSceneMood` resolver and the shared
// `SceneMoodLabel` widget — icons render NEXT TO the visible text and never
// replace it (glossary norm); an unparsable mood degrades to plain text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/material_icons.dart';
import 'package:frontend_flutter/design/scene_mood_label.dart';

void main() {
  group('BreakdownMaterialIcons.forSceneMood (issue #721)', () {
    test('canonical two-component shorthand resolves location + time', () {
      expect(BreakdownMaterialIcons.forSceneMood('I/T'), (
        Icons.home_outlined,
        Icons.wb_sunny_outlined,
      ));
      expect(BreakdownMaterialIcons.forSceneMood('A/N'), (
        Icons.park_outlined,
        Icons.dark_mode_outlined,
      ));
      expect(BreakdownMaterialIcons.forSceneMood('I/AB'), (
        Icons.home_outlined,
        Icons.bedtime_outlined,
      ));
      // D and M share the twilight icon.
      expect(
        BreakdownMaterialIcons.forSceneMood('A/D')!.$2,
        Icons.wb_twilight_outlined,
      );
      expect(
        BreakdownMaterialIcons.forSceneMood('I/M')!.$2,
        Icons.wb_twilight_outlined,
      );
    });

    test('lowercase and padded input normalizes', () {
      expect(BreakdownMaterialIcons.forSceneMood(' i/t '), (
        Icons.home_outlined,
        Icons.wb_sunny_outlined,
      ));
    });

    test('combined I/A/T resolves the combined icon once', () {
      expect(BreakdownMaterialIcons.forSceneMood('I/A/T'), (
        Icons.sensor_door_outlined,
        Icons.wb_sunny_outlined,
      ));
      expect(BreakdownMaterialIcons.forSceneMood('I/A/N'), (
        Icons.sensor_door_outlined,
        Icons.dark_mode_outlined,
      ));
    });

    test('non-shorthand values resolve to null', () {
      // Free-text mood ("tense") is not a shorthand: plain text, no icons.
      expect(BreakdownMaterialIcons.forSceneMood('tense'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood(null), isNull);
      expect(BreakdownMaterialIcons.forSceneMood(''), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('I'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('I/X'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('X/T'), isNull);
      // A three-component value other than the canonical I/A/<time>.
      expect(BreakdownMaterialIcons.forSceneMood('A/I/T'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('I/T/N'), isNull);
    });
  });

  group('SceneMoodLabel (issue #721)', () {
    testWidgets('renders the reinforcing icons next to the visible text', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SceneMoodLabel(mood: 'I/T', label: 'Mood: I/T'),
          ),
        ),
      );
      // The visible text stays the single carrier of meaning; the icons
      // reinforce it and never replace it.
      expect(find.text('Mood: I/T'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    });

    testWidgets('a non-shorthand mood renders as plain text only', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SceneMoodLabel(mood: 'tense')),
        ),
      );
      expect(find.text('tense'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.park_outlined), findsNothing);
    });

    testWidgets('the raw shorthand is the default label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SceneMoodLabel(mood: 'A/N')),
        ),
      );
      expect(find.text('A/N'), findsOneWidget);
      expect(find.byIcon(Icons.park_outlined), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    });
  });
}

// Tile-level reinforcement: the script overview tile renders the mood as its
// own icon + text line (moved out of the joined metadata string in #721).
