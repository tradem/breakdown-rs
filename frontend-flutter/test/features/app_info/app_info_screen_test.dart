// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/app_info/app_info_screen.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (route transitions settle within a
/// few frames; never `pumpAndSettle` against open-ended timers).
Future<void> pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _unknownVersionConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: 'unknown',
  defaultProjectId: '',
);

void main() {
  late ProviderContainer container;

  /// Hosts [AppInfoScreen] as a PUSHED route over a base screen (issue
  /// #653: the About surface is a full screen route — the harness mirrors
  /// that by pushing it, so the back affordance and Escape pop behave as
  /// in production) under [config], optionally with a scripted link
  /// launcher. Fresh tree per pump (view MediaQuery data is cached across
  /// `pumpWidget` — see `theme_test.dart`).
  Future<void> pumpScreen(
    WidgetTester tester, {
    AppConfig config = devAuthConfig,
    Brightness brightness = Brightness.light,
    LaunchUri? launchUri,
    double textScaler = 1.0,
    AiConfigView? aiNaming,
  }) async {
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        // The AI-notice doorway pushes the About-AI disclosure screen,
        // which reads the configured-naming discovery — overridden so the
        // push never issues a real discovery call from these tests.
        configuredAiNamingProvider.overrideWith(
          (ref) => Future.value(aiNaming),
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
        child: MediaQuery(
          data: MediaQueryData(
            platformBrightness: brightness,
            textScaler: TextScaler.linear(textScaler),
          ),
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
      Navigator.of(tester.element(find.byType(Scaffold))).push(
        MaterialPageRoute<void>(
          builder: (_) => AppInfoScreen(launchUri: launchUri),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('AppInfoScreen content (spec flutter-app-dialogs, issue #653)', () {
    testWidgets('shows version, license, source link, AI notice', (
      tester,
    ) async {
      await pumpScreen(tester);

      // Full screen route: a screen with an app bar, NOT a dialog.
      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
      expect(find.byKey(const Key('app-info-appbar')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('About Breakdown'), findsOneWidget);
      expect(find.text('1.0.0+1'), findsOneWidget);
      expect(
        find.textContaining('Affero General Public License'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('info-source-link')), findsOneWidget);
      expect(
        find.textContaining('never communicates with an AI provider'),
        findsOneWidget,
      );
    });

    testWidgets('version fallback shows unknown without the define', (
      tester,
    ) async {
      await pumpScreen(tester, config: _unknownVersionConfig);

      expect(find.text('unknown'), findsOneWidget);
    });

    testWidgets('source link opens the repository URL', (tester) async {
      Uri? launched;
      await pumpScreen(
        tester,
        launchUri: (url) async {
          launched = url;
          return true;
        },
      );

      await tester.tap(find.byKey(const Key('info-source-link')));
      await pumpFrames(tester);

      expect(launched.toString(), kSourceRepositoryUrl);
      expect(find.text('Could not open the source link.'), findsNothing);
    });

    testWidgets('failed link launch surfaces a notice, screen stays', (
      tester,
    ) async {
      await pumpScreen(tester, launchUri: (_) async => false);

      await tester.tap(find.byKey(const Key('info-source-link')));
      await pumpFrames(tester);

      expect(find.text('Could not open the source link.'), findsOneWidget);
      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
    });

    testWidgets('the app bar back affordance pops the route', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      // Bounded pumps: the pop transition (300ms) PLUS the frames the
      // framework needs to finalize the route removal afterwards.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const Key('app-info-screen')), findsNothing);
    });

    testWidgets('system back pops the route (full screen, no dialog)', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);

      // A screen route answers the SYSTEM BACK intent like any pushed
      // screen — it is not a dialog that Escape-dismisses.
      await tester.binding.handlePopRoute();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const Key('app-info-screen')), findsNothing);
    });

    testWidgets('the AI notice is the doorway: pushes the About-AI '
        'disclosure screen over the About screen (issue #538)', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('info-ai-notice')));
      // Bounded pumps past the push transition.
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      // The About screen STAYS in the stack beneath the pushed screen
      // (spec: the notice remains AND navigates; issue #653 — the route
      // is a screen, so back returns to the About surface). It is
      // offstage (covered by the opaque disclosure route), so the finder
      // must look behind it.
      expect(
        find.byKey(const Key('app-info-screen'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-disclosure-screen')), findsOneWidget);
      // The doorway hands over to the configured-naming state (none
      // configured in this harness — the honest degradation copy).
      expect(
        find.textContaining('No AI configuration is set up'),
        findsOneWidget,
      );
    });

    testWidgets('holds at textScaler 1.3 without overflow', (tester) async {
      await pumpScreen(tester, textScaler: 1.3);

      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppInfoScreen goldens (issue #653, replaces the dialog goldens)', () {
    testWidgets('light', (tester) async {
      await pumpScreen(tester, brightness: Brightness.light);
      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
      await expectLater(
        find.byType(AppInfoScreen),
        matchesGoldenFile('goldens/app_info_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      await pumpScreen(tester, brightness: Brightness.dark);
      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
      await expectLater(
        find.byType(AppInfoScreen),
        matchesGoldenFile('goldens/app_info_dark.png'),
      );
    });
  });
}
