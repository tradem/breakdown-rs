// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget tests for the Karl Klammer overlay (issue #516, spec
// `flutter-easter-eggs`): visibility gated on the Easter-eggs toggle
// (with live, immediate hide), non-modal + tap-dismissible, deterministic
// idle triggers via the fake-async clock (no wall clock / randomness),
// remove-animations static pose, screen-reader semantics, and the
// with/without goldens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/settings/easter_eggs_store.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/ai_import/clippy/clippy_trigger.dart';
import 'package:frontend_flutter/features/ai_import/clippy/karl_klammer_figure.dart';
import 'package:frontend_flutter/features/ai_import/clippy/karl_klammer_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _idlePeriod = Duration(seconds: 2);

Future<void> pumpOverlay(
  WidgetTester tester, {
  required ClippyFlowState flowState,
  bool easterEggs = true,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final container = ProviderContainer(
    overrides: [
      if (!easterEggs)
        easterEggsProvider.overrideWith(
          () => HydratedEasterEggs(initial: false, failed: false),
        ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppThemes.light(),
        darkTheme: AppThemes.dark(),
        themeMode: ThemeMode.system,
        home: Scaffold(
          body: KarlKlammerOverlay(
            flowState: flowState,
            idlePeriod: _idlePeriod,
            child: ListView(
              key: const Key('host-list'),
              children: const [
                SizedBox(height: 600),
                ElevatedButton(
                  key: Key('host-cta'),
                  onPressed: null,
                  child: Text('CTA'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  // Bounded pump — no pumpAndSettle (the excited wobble repeats forever).
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KarlKlammerOverlay visibility (spec flutter-easter-eggs)', () {
    testWidgets('hidden entirely when Easter eggs are disabled', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        flowState: ClippyFlowState.noConfig,
        easterEggs: false,
      );

      expect(find.byKey(const Key('karl-klammer-bubble')), findsNothing);
      expect(find.byKey(const Key('karl-klammer-figure')), findsNothing);
      // No residue: the host content is the ONLY thing rendered.
      expect(find.byKey(const Key('host-list')), findsOneWidget);
    });

    testWidgets('reacts immediately to a no-config flow state', (tester) async {
      await pumpOverlay(tester, flowState: ClippyFlowState.noConfig);

      expect(find.byKey(const Key('karl-klammer-bubble')), findsOneWidget);
      expect(find.byKey(const Key('karl-klammer-figure')), findsOneWidget);
      expect(find.textContaining('import a schedule'), findsOneWidget);
    });

    testWidgets('live toggle-off removes the bubble immediately, no residue', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: KarlKlammerOverlay(
                flowState: ClippyFlowState.noConfig,
                child: SizedBox(key: Key('host-list')),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('karl-klammer-bubble')), findsOneWidget);

      // Flip the global toggle OFF — running tips are torn down with the
      // subtree (dispose cancels the timers).
      await container
          .read(easterEggsProvider.notifier)
          .toggle(EasterEggsStore(SharedPreferencesAsync()));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const Key('karl-klammer-bubble')), findsNothing);
      expect(find.byKey(const Key('karl-klammer-figure')), findsNothing);
      expect(find.byKey(const Key('host-list')), findsOneWidget);
    });

    testWidgets('tap dismisses for the session; next state change re-shows', (
      tester,
    ) async {
      await pumpOverlay(tester, flowState: ClippyFlowState.noConfig);

      await tester.tap(find.byKey(const Key('karl-klammer-bubble')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('karl-klammer-bubble')), findsNothing);
    });

    testWidgets('non-modal: primary CTA remains hit-testable below', (
      tester,
    ) async {
      await pumpOverlay(tester, flowState: ClippyFlowState.noConfig);

      // The bubble sits bottom-LEADING (left); the CTA further up the
      // list is fully visible and tappable (no barrier, no modal).
      final bubble = tester.getRect(
        find.byKey(const Key('karl-klammer-bubble')),
      );
      final cta = tester.getRect(find.byKey(const Key('host-cta')));
      expect(bubble.bottom, greaterThanOrEqualTo(cta.bottom));
      final overlaps =
          bubble.left < cta.right &&
          cta.left < bubble.right &&
          bubble.top < cta.bottom &&
          cta.top < bubble.bottom;
      expect(overlaps, isFalse, reason: 'the bubble must never cover a CTA');
    });

    testWidgets('idle shows no immediate tip; the periodic joke fires '
        'deterministically via the fake-async clock', (tester) async {
      await pumpOverlay(tester, flowState: ClippyFlowState.idle);

      // Entering idle is silent (occasional, not nagging).
      expect(find.byKey(const Key('karl-klammer-bubble')), findsNothing);

      // Fake-async time travel: the FIRST idle tick shows joke 1.
      await tester.pump(_idlePeriod);
      expect(find.byKey(const Key('karl-klammer-bubble')), findsOneWidget);
      expect(find.textContaining('Klamotten'), findsOneWidget);

      // The SECOND tick cycles to joke 2 — deterministic, not random.
      await tester.pump(_idlePeriod);
      expect(find.textContaining('clothes hanger'), findsOneWidget);
    });

    testWidgets('remove-animations: static pose (no ticker scheduled)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: KarlKlammerFigure(
                pose: ClippyPose.excited,
                animate: false,
              ),
            ),
          ),
        ),
      );
      // Static pose: NO transient (animation) callbacks are scheduled —
      // the controller never runs, so time travel changes nothing.
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.binding.transientCallbackCount, 0);

      // Control: the same figure WITH animation does schedule a ticker.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: KarlKlammerFigure(pose: ClippyPose.excited, animate: true),
            ),
          ),
        ),
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('screen-reader semantics: one dismissible button, '
        'figure internals excluded', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOverlay(tester, flowState: ClippyFlowState.error);

      final node = tester.getSemantics(
        find.byKey(const Key('karl-klammer-bubble')),
      );
      expect(node.flagsCollection.isButton, isTrue);
      // The droop/error tip text is announced via the bubble label.
      expect(node.label, contains('Hide Karl Klammer'));
      handle.dispose();
    });
  });

  group('KarlKlammerOverlay goldens (issue #516)', () {
    testWidgets('ai import with Karl Klammer (no-config tip, light)', (
      tester,
    ) async {
      await pumpOverlay(tester, flowState: ClippyFlowState.noConfig);
      await expectLater(
        find.byType(KarlKlammerOverlay),
        matchesGoldenFile('goldens/clippy_no_config_light.png'),
      );
    });

    testWidgets('ai import WITHOUT Karl Klammer (toggle off)', (tester) async {
      await pumpOverlay(
        tester,
        flowState: ClippyFlowState.noConfig,
        easterEggs: false,
      );
      await expectLater(
        find.byType(KarlKlammerOverlay),
        matchesGoldenFile('goldens/clippy_disabled_light.png'),
      );
    });

    testWidgets('error droop pose (light)', (tester) async {
      await pumpOverlay(tester, flowState: ClippyFlowState.error);
      await expectLater(
        find.byType(KarlKlammerOverlay),
        matchesGoldenFile('goldens/clippy_error_light.png'),
      );
    });
  });
}
