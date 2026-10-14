// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/auth_providers.dart'
    show appConfigProvider;
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/app_info/app_info_controller.dart';
import 'package:frontend_flutter/features/app_info/app_info_screen.dart';
import 'package:frontend_flutter/features/app_info/credits_screen.dart';

import '../seasons/seasons_test_fakes.dart' show devAuthConfig;

/// Fixed wire payload (backend order: sorted LLM co-authors, then humans) —
/// the deterministic fixture for content tests and goldens.
MetaCreditsResponse get _fixture => MetaCreditsResponse(
  (b) => b
    ..credits.addAll([
      _llm('deepseek-v4-flash', 'neuralwatt'),
      _llm('glm-5.3', 'neuralwatt'),
      _human('digiwitcher', ['Developer']),
      _human('imacRic', ['Product Owner', 'Tester']),
    ]),
);

MetaCreditsEntry _llm(String name, String provider) => MetaCreditsEntry(
  (b) => b
    ..name = name
    ..provider = provider
    ..roles.addAll([]),
);

MetaCreditsEntry _human(String name, List<String> roles) => MetaCreditsEntry(
  (b) => b
    ..name = name
    ..provider = null
    ..roles.addAll(roles),
);

/// Pumps a bounded number of frames (route transitions settle within a few
/// frames; never `pumpAndSettle` against open-ended timers).
Future<void> pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late ProviderContainer container;

  /// Hosts [CreditsScreen] as a PUSHED route over a base screen (mirrors the
  /// production navigation from the About screen) with the credits fetch
  /// overridden to [metaCreditsFetch] so tests script the data/error/loading
  /// states deterministically.
  Future<void> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    TargetPlatform platform = TargetPlatform.android,
    Future<MetaCreditsResponse> Function()? metaCreditsFetch,
  }) async {
    container = ProviderContainer(
      // Riverpod 3 auto-retries failed providers on a timer — the scripted
      // error state must not leave a pending timer at teardown.
      retry: (_, _) => null,
      overrides: [
        metaCreditsProvider.overrideWith(
          (ref) =>
              metaCreditsFetch?.call() ??
              Future<MetaCreditsResponse>.value(_fixture),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    // Fire-and-forget: the pushed route's pop result is not a consumable
    // value in the harness.
    unawaited(
      Navigator.of(tester.element(find.byType(Scaffold)))
          .push(MaterialPageRoute<void>(builder: (_) => const CreditsScreen())),
    );
    await pumpFrames(tester);
    // Reset INSIDE the test body: leaving the foundation debug var set trips
    // the binding's end-of-test invariant (the addTearDown above fires too
    // late — same discipline as the ai_disclosure golden harness).
    debugDefaultTargetPlatformOverride = null;
  }

  group('CreditsScreen content (issue #655)', () {
    testWidgets('renders every co-author exactly once (deduped payload)', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      expect(find.byKey(const Key('credits-cloud')), findsOneWidget);
      // Each name appears exactly once — the backend dedupes per
      // (model, provider); the client must not re-duplicate.
      expect(find.text('glm-5.3'), findsOneWidget);
      expect(find.text('deepseek-v4-flash'), findsOneWidget);
      expect(find.text('digiwitcher'), findsOneWidget);
      expect(find.text('imacRic'), findsOneWidget);
    });

    testWidgets('humans are visually distinguishable via their role labels', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Developer'), findsOneWidget);
      expect(find.text('Product Owner'), findsOneWidget);
      expect(find.text('Tester'), findsOneWidget);
      // LLM terms carry no role captions.
      expect(
        find.descendant(
          of: find.byKey(const Key('credit-term-glm-5.3')),
          matching: find.text('neuralwatt'),
        ),
        findsNothing,
      );
    });

    testWidgets('cloud terms are reachable for screen readers via semantic '
        'labels, not just painted text', (tester) async {
      await pumpScreen(tester);

      // The human term's semantics carry the name AND its roles…
      expect(
        tester.getSemantics(find.byKey(const Key('credit-term-digiwitcher'))),
        isSemantics(label: 'digiwitcher, Developer'),
      );
      // …and the LLM term's semantics carry the name AND the provider.
      expect(
        tester.getSemantics(find.byKey(const Key('credit-term-glm-5.3'))),
        isSemantics(label: 'glm-5.3, AI co-author by neuralwatt'),
      );
    });

    testWidgets('the word cloud layout is deterministic across rebuilds', (
      tester,
    ) async {
      await pumpScreen(tester);
      final first = tester.getRect(find.byKey(const Key('credits-cloud')));

      // Force a rebuild: same payload, same hash-derived tiers, same layout.
      await tester.pump();
      final second = tester.getRect(find.byKey(const Key('credits-cloud')));

      expect(second, first);
    });

    testWidgets('a failed credits fetch degrades gracefully', (tester) async {
      await pumpScreen(
        tester,
        metaCreditsFetch: () =>
            Future.error(const ProblemError(code: 'auth.unauthenticated')),
      );

      // The screen STAYS and shows the honest error copy — never a crash,
      // never a discarded error (no-silent-discard rule).
      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('credits-error')), findsOneWidget);
    });

    testWidgets('an in-flight credits fetch shows the loading hint', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        metaCreditsFetch: () => Completer<MetaCreditsResponse>().future,
      );

      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('credits-loading')), findsOneWidget);
    });

    testWidgets('shows the "Auf der Schulter von Riesen" section with the '
        'Rust and Flutter logos', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('credits-shoulders')), findsOneWidget);
      // Content tests run in the default (English) test locale.
      expect(find.text('On the shoulders of giants'), findsOneWidget);
      expect(find.byKey(const Key('credits-rust-logo')), findsOneWidget);
      expect(find.byKey(const Key('credits-flutter-logo')), findsOneWidget);
      // Both SVG assets actually rendered (no missing-asset exception).
      expect(tester.takeException(), isNull);
    });

    testWidgets('the app bar back affordance pops the route', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const Key('credits-screen')), findsNothing);
    });
  });

  group('CreditsScreen goldens (issue #655)', () {
    testWidgets('golden light android', (tester) async {
      await pumpScreen(
        tester,
        brightness: Brightness.light,
        platform: TargetPlatform.android,
      );
      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      await expectLater(
        find.byType(CreditsScreen),
        matchesGoldenFile('goldens/credits_light_android.png'),
      );
    });

    testWidgets('golden dark android', (tester) async {
      await pumpScreen(
        tester,
        brightness: Brightness.dark,
        platform: TargetPlatform.android,
      );
      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      await expectLater(
        find.byType(CreditsScreen),
        matchesGoldenFile('goldens/credits_dark_android.png'),
      );
    });

    testWidgets('golden light macos', (tester) async {
      await pumpScreen(
        tester,
        brightness: Brightness.light,
        platform: TargetPlatform.macOS,
      );
      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      await expectLater(
        find.byType(CreditsScreen),
        matchesGoldenFile('goldens/credits_light_macos.png'),
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await pumpScreen(
        tester,
        brightness: Brightness.dark,
        platform: TargetPlatform.macOS,
      );
      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      await expectLater(
        find.byType(CreditsScreen),
        matchesGoldenFile('goldens/credits_dark_macos.png'),
      );
    });
  });

  group('CreditsScreen doorway (issue #655)', () {
    testWidgets('the About screen info-credits tile pushes the credits '
        'screen over the About screen', (tester) async {
      // Minimal About harness (same pattern as app_info_screen_test): the
      // meta versions fetch is overridden so the push never issues a real
      // client call from these tests.
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          metaVersionsProvider.overrideWith(
            (ref) => Future<MetaVersionsResponse>.value(
              MetaVersionsResponse(
                (b) => b
                  ..api = '0.26.0'
                  ..core = '0.28.0'
                  ..infra = '0.33.0',
              ),
            ),
          ),
          metaCreditsProvider.overrideWith(
            (ref) => Future<MetaCreditsResponse>.value(_fixture),
          ),
        ],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await pumpFrames(tester);
      unawaited(
        Navigator.of(
          tester.element(find.byType(Scaffold)),
        ).push(MaterialPageRoute<void>(builder: (_) => const AppInfoScreen())),
      );
      await pumpFrames(tester);

      await tester.tap(find.byKey(const Key('info-credits')));
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      // The About screen STAYS in the stack beneath the pushed credits
      // screen; the cloud renders from the overridden payload.
      expect(
        find.byKey(const Key('app-info-screen'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const Key('credits-screen')), findsOneWidget);
      expect(find.byKey(const Key('credits-cloud')), findsOneWidget);
    });
  });
}
