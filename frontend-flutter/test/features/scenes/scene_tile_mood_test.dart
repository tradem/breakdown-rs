// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

// Tier-2 widget test for the script overview tile's mood reinforcement line
// (issue #721): a canonical shorthand mood renders its icons next to the
// visible `Mood: I/T` text on its own line; a free-text mood stays plain.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/scenes/scenes_state.dart';
import 'package:frontend_flutter/features/scenes/widgets/scenes_widgets.dart';

void main() {
  SceneView scene({String? mood}) => SceneView(
    (b) => b
      ..id = 'scene-1'
      ..episodeId = 'episode-1'
      ..sceneNumber = 7
      ..isScheduleSet = false
      ..mood = mood
      ..summary = 'A scene'
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  );

  testWidgets('shorthand mood renders icons next to the visible text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTile(row: ProjectedSceneRow(scene(mood: 'I/T'))),
        ),
      ),
    );
    // The visible localized label + both reinforcing icons, keyed for tests.
    expect(find.byKey(const Key('scene-mood-scene-1')), findsOneWidget);
    expect(find.textContaining('Mood: I/T'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
  });

  testWidgets('free-text mood renders its line without icons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTile(row: ProjectedSceneRow(scene(mood: 'tense'))),
        ),
      ),
    );
    expect(find.byKey(const Key('scene-mood-scene-1')), findsOneWidget);
    expect(find.textContaining('Mood: tense'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
  });

  testWidgets('no mood renders no mood line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SceneTile(row: ProjectedSceneRow(scene()))),
      ),
    );
    expect(find.byKey(const Key('scene-mood-scene-1')), findsNothing);
    expect(find.textContaining('Mood:'), findsNothing);
  });
}
