// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/app_info/info_dialog.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (dialog entrance animation settles
/// within a few frames; never `pumpAndSettle` against open-ended timers).
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
  defaultSeriesId: '',
);

void main() {
  late ProviderContainer container;

  /// Host scaffold under [config]; opens the dialog (optionally with a
  /// scripted link launcher). Fresh tree per pump (view MediaQuery data is
  /// cached across `pumpWidget` — see `theme_test.dart`).
  Future<void> pumpDialog(
    WidgetTester tester, {
    AppConfig config = devAuthConfig,
    Brightness brightness = Brightness.light,
    LaunchUri? launchUri,
    double textScaler = 1.0,
  }) async {
    container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(config)],
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
    unawaited(
      showAppInfoDialog(
        tester.element(find.byType(Scaffold)),
        launchUri: launchUri,
      ),
    );
    await pumpFrames(tester);
  }

  group('InfoDialog content (task 5.1/5.2)', () {
    testWidgets('shows version, license, source link, AI notice', (
      tester,
    ) async {
      await pumpDialog(tester);

      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
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
      await pumpDialog(tester, config: _unknownVersionConfig);

      expect(find.text('unknown'), findsOneWidget);
    });

    testWidgets('source link opens the repository URL', (tester) async {
      Uri? launched;
      await pumpDialog(
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

    testWidgets('failed link launch surfaces a notice, dialog stays', (
      tester,
    ) async {
      await pumpDialog(tester, launchUri: (_) async => false);

      await tester.tap(find.byKey(const Key('info-source-link')));
      await pumpFrames(tester);

      expect(find.text('Could not open the source link.'), findsOneWidget);
      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
    });

    testWidgets('close button dismisses the dialog', (tester) async {
      await pumpDialog(tester);
      expect(find.byKey(const Key('info-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('info-close')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('info-dialog')), findsNothing);
    });

    testWidgets('Escape closes the dialog', (tester) async {
      await pumpDialog(tester);
      expect(find.byKey(const Key('info-dialog')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);

      expect(find.byKey(const Key('info-dialog')), findsNothing);
    });

    testWidgets('holds at textScaler 1.3 without overflow', (tester) async {
      await pumpDialog(tester, textScaler: 1.3);

      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('InfoDialog goldens (task 5.2)', () {
    testWidgets('light', (tester) async {
      await pumpDialog(tester, brightness: Brightness.light);
      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
      await expectLater(
        find.byType(AppInfoDialog),
        matchesGoldenFile('goldens/info_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      await pumpDialog(tester, brightness: Brightness.dark);
      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
      await expectLater(
        find.byType(AppInfoDialog),
        matchesGoldenFile('goldens/info_dark.png'),
      );
    });
  });
}
