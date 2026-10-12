// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Tier-1 + Tier-2 tests for the redesigned Karl Klammer figure (issue
// #614): the pure blink curve, the comic-vector pose rendering (goldens
// per ClippyPose), the deterministic repaint/blink phase proofs, and the
// design-token discipline (no raw color literals in the painter).

import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/ai_import/clippy/clippy_trigger.dart';
import 'package:frontend_flutter/features/ai_import/clippy/karl_klammer_figure.dart';

Future<void> pumpFigure(
  WidgetTester tester, {
  required ClippyPose pose,
  required bool animate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: KarlKlammerFigure(pose: pose, animate: animate),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('karlEyesClosed (issue #614)', () {
    test('is a pure, deterministic function of the phase', () {
      expect(karlEyesClosed(0.0), isFalse);
      expect(karlEyesClosed(0.25), isFalse);
      expect(karlEyesClosed(0.48), isTrue);
      expect(karlEyesClosed(0.50), isTrue);
      expect(karlEyesClosed(0.52), isTrue);
      expect(karlEyesClosed(0.53), isFalse);
      expect(karlEyesClosed(1.0), isFalse);
    });
  });

  group('body-motion continuity (issue #614 / review #627)', () {
    test('every pose completes whole cycles per controller restart', () {
      for (final pose in ClippyPose.values) {
        // Continuous phase: the end of the cycle equals the start, so
        // there is no jump when the 4200 ms controller restarts.
        expect(
          karlBodyPhase(pose, 1.0),
          closeTo(karlBodyPhase(pose, 0.0), 1e-9),
          reason: '${pose.name} must be continuous at the cycle boundary',
        );
      }
    });
  });

  group('comic-vector pose rendering (issue #614)', () {
    for (final pose in ClippyPose.values) {
      testWidgets('renders the ${pose.name} pose (static golden)', (
        tester,
      ) async {
        await pumpFigure(tester, pose: pose, animate: false);
        await expectLater(
          find.byType(KarlKlammerFigure),
          matchesGoldenFile('goldens/karl_pose_${pose.name}.png'),
        );
      });
    }

    test('every pose golden differs byte-wise (distinct expressions)', () {
      // A broken expression switch would collapse poses onto one render.
      final bytes = {
        for (final pose in ClippyPose.values)
          pose.name: File(
            'test/features/ai_import/goldens/karl_pose_${pose.name}.png',
          ).readAsBytesSync(),
      };
      final names = bytes.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          expect(
            listEquals(bytes[names[i]], bytes[names[j]]),
            isFalse,
            reason: '${names[i]} and ${names[j]} must render differently',
          );
        }
      }
    });
  });

  group('animation determinism (issue #614)', () {
    testWidgets('idle motion repaints each phase (neutral pose)', (
      tester,
    ) async {
      await pumpFigure(tester, pose: ClippyPose.neutral, animate: true);
      // Two distinct body-motion phases of the neutral signature.
      await tester.pump(const Duration(milliseconds: 900));
      await expectLater(
        find.byType(KarlKlammerFigure),
        matchesGoldenFile('goldens/karl_motion_phase_a.png'),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await expectLater(
        find.byType(KarlKlammerFigure),
        matchesGoldenFile('goldens/karl_motion_phase_b.png'),
      );
    });

    test('the two motion phase goldens differ byte-wise (repaint proof)', () {
      final a = File('test/features/ai_import/goldens/karl_motion_phase_a.png')
          .readAsBytesSync();
      final b = File('test/features/ai_import/goldens/karl_motion_phase_b.png')
          .readAsBytesSync();
      // If the controller tick were not wired to the painter, both phases
      // would render identically.
      expect(listEquals(a, b), isFalse);
    });

    testWidgets('blink renders a closed-eye frame at the blink phase', (
      tester,
    ) async {
      await pumpFigure(tester, pose: ClippyPose.neutral, animate: true);
      // Phase 0.0 → eyes open.
      await expectLater(
        find.byType(KarlKlammerFigure),
        matchesGoldenFile('goldens/karl_blink_open.png'),
      );
      // Phase 0.5 → inside the deterministic blink window (eyes closed).
      await tester.pump(const Duration(milliseconds: 2100));
      await expectLater(
        find.byType(KarlKlammerFigure),
        matchesGoldenFile('goldens/karl_blink_closed.png'),
      );
    });

    test('the blink open/closed goldens differ byte-wise', () {
      final open = File('test/features/ai_import/goldens/karl_blink_open.png')
          .readAsBytesSync();
      final closed = File(
        'test/features/ai_import/goldens/karl_blink_closed.png',
      ).readAsBytesSync();
      expect(listEquals(open, closed), isFalse);
    });

    testWidgets('disabling animation repaints to the static pose', (
      tester,
    ) async {
      // Repaint proof for shouldRepaint comparing _motion (review #627):
      // pump to a blink-closed frame, then flip animate to false. If the
      // painter did not repaint, the stale closed-eye frame would remain
      // and this static-pose golden would mismatch.
      await pumpFigure(tester, pose: ClippyPose.neutral, animate: true);
      await tester.pump(const Duration(milliseconds: 2100));
      await pumpFigure(tester, pose: ClippyPose.neutral, animate: false);
      await expectLater(
        find.byType(KarlKlammerFigure),
        matchesGoldenFile('goldens/karl_pose_neutral.png'),
      );
    });
  });

  group('design-token discipline (issue #614)', () {
    test('the figure source contains no raw color literals', () {
      final source = File(
        'lib/features/ai_import/clippy/karl_klammer_figure.dart',
      ).readAsStringSync();
      expect(source.contains('Color(0x'), isFalse);
      expect(source.contains('Color.fromARGB'), isFalse);
      expect(source.contains('Colors.'), isFalse);
    });
  });
}
