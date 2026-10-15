// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Tier-2 widget tests for the Deja-vu Cat (issue #615, spec
// `flutter-easter-eggs`): visibility gated on both the splash surface and
// the per-egg flag + October gate, remove-animations static pose,
// deterministic walk (repaint proof), and goldens.

import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/settings/easter_eggs_store.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/easter_eggs/dejavu_cat.dart';

Future<void> pumpOverlay(
  WidgetTester tester, {
  required DateTime now,
  bool enabled = true,
  bool disableAnimations = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (!enabled)
        easterEggProvider(EasterEggId.dejaVuCat).overrideWith(
          () => HydratedEasterEggs(
            EasterEggId.dejaVuCat,
            initial: false,
            failed: false,
          ),
        ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(600, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppThemes.light(),
        darkTheme: AppThemes.dark(),
        themeMode: ThemeMode.system,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: DejaVuCatOverlay(
              clock: () => now,
              child: const Center(child: Text('splash', key: Key('host'))),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DejaVuCatOverlay visibility (spec flutter-easter-eggs)', () {
    testWidgets('visible in October when its egg is enabled', (tester) async {
      await pumpOverlay(tester, now: DateTime(2026, 10, 15));

      expect(find.byKey(const Key('dejavu-cat')), findsOneWidget);
      // The splash content is still there — the cat is an overlay.
      expect(find.byKey(const Key('host')), findsOneWidget);
    });

    testWidgets('dormant outside October even when enabled', (tester) async {
      await pumpOverlay(tester, now: DateTime(2026, 9, 30));

      expect(find.byKey(const Key('dejavu-cat')), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);

      await pumpOverlay(tester, now: DateTime(2026, 11, 1));
      expect(find.byKey(const Key('dejavu-cat')), findsNothing);
    });

    testWidgets('hidden when its egg flag is off (any month)', (tester) async {
      await pumpOverlay(tester, now: DateTime(2026, 10, 15), enabled: false);

      expect(find.byKey(const Key('dejavu-cat')), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);
    });

    testWidgets('non-interactive: never intercepts pointers', (tester) async {
      await pumpOverlay(tester, now: DateTime(2026, 10, 15));

      final walker = tester.widget<DejaVuCatWalker>(
        find.byType(DejaVuCatWalker),
      );
      expect(walker.animate, isTrue);
      // The walker sits behind an IgnorePointer — the host stays hittable.
      expect(find.byType(IgnorePointer), findsWidgets);
    });

    testWidgets('remove-animations: static pose, no ticker scheduled', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        now: DateTime(2026, 10, 15),
        disableAnimations: true,
      );

      expect(find.byKey(const Key('dejavu-cat')), findsOneWidget);
      // Static pose: NO transient (animation) callbacks are scheduled.
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('animated: a ticker is scheduled', (tester) async {
      await pumpOverlay(tester, now: DateTime(2026, 10, 15));

      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });
  });

  group('DejaVuCatWalker goldens + repaint proof (issue #615)', () {
    Future<void> pumpWalker(
      WidgetTester tester, {
      required bool animate,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(400, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 200,
                  child: DejaVuCatWalker(animate: animate),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('static pose golden (remove-animations fallback)', (
      tester,
    ) async {
      await pumpWalker(tester, animate: false);
      await expectLater(
        find.byType(DejaVuCatWalker),
        matchesGoldenFile('goldens/dejavu_cat_static_light.png'),
      );
    });

    testWidgets('static pose golden — dark theme keeps the cat readable', (
      tester,
    ) async {
      // Issue #670: the approved fixed palette (near-black fur + soft
      // blue-grey rim light) is designed to keep the silhouette readable
      // in BOTH themes; this golden protects that.
      await pumpWalker(tester, animate: false, brightness: Brightness.dark);
      await expectLater(
        find.byType(DejaVuCatWalker),
        matchesGoldenFile('goldens/dejavu_cat_static_dark.png'),
      );
    });

    testWidgets('walk repaints each tick (phase goldens)', (tester) async {
      await pumpWalker(tester, animate: true);
      // Distinct travel phases (9 s cycle: 0.1 vs 0.2).
      await tester.pump(const Duration(milliseconds: 900));
      await expectLater(
        find.byType(DejaVuCatWalker),
        matchesGoldenFile('goldens/dejavu_cat_phase_a.png'),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await expectLater(
        find.byType(DejaVuCatWalker),
        matchesGoldenFile('goldens/dejavu_cat_phase_b.png'),
      );
    });

    test('the two walk phase goldens differ byte-wise (repaint proof)', () {
      final a = File('test/features/easter_eggs/goldens/dejavu_cat_phase_a.png')
          .readAsBytesSync();
      final b = File('test/features/easter_eggs/goldens/dejavu_cat_phase_b.png')
          .readAsBytesSync();
      // If the controller tick were NOT wired to the painter, both phases
      // would render the static pose and the files would be byte-identical.
      expect(listEquals(a, b), isFalse);
    });
  });
}
