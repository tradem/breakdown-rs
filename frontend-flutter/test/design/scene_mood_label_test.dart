// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 tests for the set-shorthand mood reinforcement (issue #721): the
// `BreakdownMaterialIcons.forSceneMood` resolver and the shared
// `SceneMoodLabel` widget — icons render NEXT TO the visible text and never
// replace it (glossary norm); an unparsable mood degrades to plain text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/material_icons.dart';
import 'package:frontend_flutter/design/scene_mood_label.dart';

void main() {
  group('BreakdownMaterialIcons.forSceneMood (issues #721, #834 follow-up)', () {
    /// Asserts the resolved icons of [mood] field by field — a record holding a
    /// [List] compares its list by IDENTITY, so the location icons are compared
    /// with a value matcher instead.
    void expectIcons(String mood, List<IconData> locations, IconData time) {
      final icons = BreakdownMaterialIcons.forSceneMood(mood);
      expect(icons, isNotNull, reason: mood);
      expect(icons!.locations, locations, reason: mood);
      expect(icons.time, time, reason: mood);
    }

    test('canonical two-component shorthand resolves location + time', () {
      expectIcons('I/T', [Icons.home_outlined], Icons.wb_sunny_outlined);
      expectIcons('A/N', [Icons.park_outlined], Icons.dark_mode_outlined);
      expectIcons('I/AB', [Icons.home_outlined], Icons.bedtime_outlined);
      // D and M share the twilight icon.
      expectIcons('A/D', [Icons.park_outlined], Icons.wb_twilight_outlined);
      expectIcons('I/M', [Icons.home_outlined], Icons.wb_twilight_outlined);
    });

    test('lowercase and padded input normalizes', () {
      expectIcons(' i/t ', [Icons.home_outlined], Icons.wb_sunny_outlined);
    });

    test('a MIXED shorthand resolves to one threshold icon', () {
      // `I/A/T` (INT./EXT.) and `A/I/T` ("outside at the street, then inside
      // the clinic" — the reported live case) name the same fact: the scene
      // crosses the threshold. Both orders must render, and both must render
      // the SAME thing.
      expectIcons('I/A/T', [
        Icons.sensor_door_outlined,
      ], Icons.wb_sunny_outlined);
      expectIcons('A/I/T', [
        Icons.sensor_door_outlined,
      ], Icons.wb_sunny_outlined);
      expectIcons('I/A/N', [
        Icons.sensor_door_outlined,
      ], Icons.dark_mode_outlined);
      expectIcons('A/I/AB', [
        Icons.sensor_door_outlined,
      ], Icons.bedtime_outlined);
    });

    test('repeated locations render one icon each', () {
      // Not a threshold crossing: the same side twice keeps its own icons.
      expectIcons('A/A/T', [
        Icons.park_outlined,
        Icons.park_outlined,
      ], Icons.wb_sunny_outlined);
    });

    test('non-shorthand values resolve to null', () {
      // Free-text mood ("tense") is not a shorthand: plain text, no icons.
      expect(BreakdownMaterialIcons.forSceneMood('tense'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood(null), isNull);
      expect(BreakdownMaterialIcons.forSceneMood(''), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('I'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('I/X'), isNull);
      expect(BreakdownMaterialIcons.forSceneMood('X/T'), isNull);
      // More than three location components is not a shorthand this pipeline
      // knows: no icons rather than a guessed set.
      expect(BreakdownMaterialIcons.forSceneMood('I/A/I/A/T'), isNull);
      // A component after the time token is not a location either.
      expect(BreakdownMaterialIcons.forSceneMood('I/A/T/N'), isNull);
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

    testWidgets('a MIXED mood renders its icons too (issue #834 follow-up)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SceneMoodLabel(mood: 'A/I/T')),
        ),
      );
      expect(find.text('A/I/T'), findsOneWidget);
      expect(find.byIcon(Icons.sensor_door_outlined), findsOneWidget);
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
