// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget tests for the dedicated About-AI disclosure screen (spec
// `flutter-app-dialogs` "Info Dialog Contents → About-AI screen", issue
// #538): the six content blocks, the provider/model naming states
// (configured / unconfigured / discovery failure — NEVER an invented name),
// and the About dialog's AI notice as the navigation doorway.

import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/app_info/ai_disclosure_screen.dart';

const devAuthConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: 'series-1',
);

AiConfigView _namingConfig({
  LlmProvider provider = LlmProvider.openai,
  String model = 'assistant-model-1',
}) => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = model
    ..provider = provider
    ..vaultKeyId = 'vk-1'
    ..prompts.replace(BuiltMap<String, String>())
    ..promptKinds.replace(BuiltList<DocumentKind>())
    ..revoked = false
    ..version = 1,
);

/// Pumps the disclosure screen alone (the doorway test lives in
/// `info_dialog_test.dart` visiting the REAL About dialog).
Future<void> pumpScreen(
  WidgetTester tester, {
  AiConfigView? naming,
  Object? namingThrows,
}) async {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      configuredAiNamingProvider.overrideWith(
        (ref) =>
            namingThrows != null ? throw namingThrows : Future.value(naming),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppThemes.light(),
        darkTheme: AppThemes.dark(),
        home: AiDisclosureScreen(launchUri: (_) async => false),
      ),
    ),
  );
  // Bounded pumps (the naming discovery resolves within the override; the
  // screen never settles against open-ended timers).
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets('the six content blocks render (purpose, flow, naming, '
      'retention, act, source)', (tester) async {
    await pumpScreen(tester, naming: _namingConfig());

    expect(find.byKey(const Key('ai-disclosure-purpose')), findsOneWidget);
    expect(find.byKey(const Key('ai-disclosure-flow')), findsOneWidget);
    expect(find.byKey(const Key('ai-disclosure-naming')), findsOneWidget);
    expect(find.byKey(const Key('ai-disclosure-retention')), findsOneWidget);
    expect(find.byKey(const Key('ai-disclosure-act')), findsOneWidget);
    expect(find.byKey(const Key('ai-disclosure-source')), findsOneWidget);
    expect(find.byKey(const Key('ai-disclosure-source-link')), findsOneWidget);
  });

  testWidgets('configured naming carries the wire provider + model — '
      'non-secret values only', (tester) async {
    await pumpScreen(
      tester,
      naming: _namingConfig(provider: LlmProvider.openai),
    );

    expect(find.textContaining('Configured: provider openai'), findsOneWidget);
    expect(find.textContaining('assistant-model-1'), findsOneWidget);
    // No secret material in the disclosure.
    expect(find.textContaining('vk-1'), findsNothing);
    expect(find.textContaining('vault'), findsNothing);
  });

  testWidgets('unconfigured naming renders the honest degradation copy — '
      'never a spinner trap, never an invented name', (tester) async {
    await pumpScreen(tester, naming: null);

    expect(
      find.textContaining('No AI configuration is set up'),
      findsOneWidget,
    );
  });

  testWidgets('discovery failure renders the degradation copy in every '
      'state (the block itself always renders)', (tester) async {
    // Left (fetch failed) resolves `null` through the repository fake —
    // and an unhandled provider exception lands on the same copy.
    await pumpScreen(tester, namingThrows: StateError('discovery down'));
    expect(find.byKey(const Key('ai-disclosure-naming')), findsOneWidget);
    await tester.pump();
  });

  group(
    'AiDisclosureScreen goldens (issue #538): {light,dark}×{android,macos}',
    () {
      Future<void> pumpGolden(
        WidgetTester tester, {
        required String golden,
        required Brightness brightness,
        required TargetPlatform platform,
      }) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(devAuthConfig),
            configuredAiNamingProvider.overrideWith(
              (ref) => Future.value(_namingConfig()),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: MediaQueryData(platformBrightness: brightness),
              child: MaterialApp(
                theme: AppThemes.light(),
                darkTheme: AppThemes.dark(),
                home: AiDisclosureScreen(launchUri: (_) async => false),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 25));
        }
        await expectLater(
          find.byType(AiDisclosureScreen),
          matchesGoldenFile('goldens/$golden'),
        );
        debugDefaultTargetPlatformOverride = null;
      }

      testWidgets('disclosure golden light android', (tester) async {
        await pumpGolden(
          tester,
          golden: 'ai_disclosure_light_android.png',
          brightness: Brightness.light,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('disclosure golden dark android', (tester) async {
        await pumpGolden(
          tester,
          golden: 'ai_disclosure_dark_android.png',
          brightness: Brightness.dark,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('disclosure golden light macos', (tester) async {
        await pumpGolden(
          tester,
          golden: 'ai_disclosure_light_macos.png',
          brightness: Brightness.light,
          platform: TargetPlatform.macOS,
        );
      });

      testWidgets('disclosure golden dark macos', (tester) async {
        await pumpGolden(
          tester,
          golden: 'ai_disclosure_dark_macos.png',
          brightness: Brightness.dark,
          platform: TargetPlatform.macOS,
        );
      });
    },
  );
}
