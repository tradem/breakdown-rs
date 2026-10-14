// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Widget + golden tests (issue #657): the backend health pill in each of
// its four tiers, with semantic finders (find.text), theme-token color
// assertions per brightness, and the empty-until-first-answer behavior.
// Goldens use the German template locale (AGENTS.md §6) in light AND dark.
// The controller is frozen per tier via overrideWithValue — no probe, no timers
// (deterministic-tests hard rule); its state machine is covered in
// test/unit/backend_health_providers_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/shell/backend_health_pill.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/src/health/backend_health_providers.dart';

/// German labels (template locale) per tier.
const _deLabels = {
  BackendHealthTier.healthy: 'Backend bereit',
  BackendHealthTier.degraded: 'Backend eingeschränkt',
  BackendHealthTier.unhealthy: 'Backend gestört',
  BackendHealthTier.offline: 'Backend nicht erreichbar',
};

/// English labels (test locale) per tier.
const _enLabels = {
  BackendHealthTier.healthy: 'Backend ready',
  BackendHealthTier.degraded: 'Backend degraded',
  BackendHealthTier.unhealthy: 'Backend impaired',
  BackendHealthTier.offline: 'Backend unreachable',
};

/// The DTCG semantic status token per tier, resolved per brightness —
/// degraded/offline share the error family with the #654 offline pill.
Color _expectedColor(BackendHealthTier tier, Brightness brightness) =>
    switch (tier) {
      BackendHealthTier.healthy =>
        brightness == Brightness.light
            ? DesignTokens.colorSemanticSuccessLight
            : DesignTokens.colorSemanticSuccessDark,
      BackendHealthTier.degraded =>
        brightness == Brightness.light
            ? DesignTokens.colorSemanticWarningLight
            : DesignTokens.colorSemanticWarningDark,
      BackendHealthTier.unhealthy || BackendHealthTier.offline =>
        brightness == Brightness.light
            ? DesignTokens.colorSemanticErrorLight
            : DesignTokens.colorSemanticErrorDark,
    };

void main() {
  /// Pumps the pill alone under a frozen controller tier. The overridden
  /// build NEVER polls (it just returns the tier), so no probe/Dio activity
  /// and no pending timers.
  Future<void> pumpPill(
    WidgetTester tester, {
    required BackendHealthTier? tier,
    required Brightness brightness,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendHealthControllerProvider.overrideWithValue(tier)],
        child: MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const Scaffold(body: Center(child: BackendHealthPill())),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color iconColorOf(WidgetTester tester) {
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('profile-health-pill')),
        matching: find.byType(Icon),
      ),
    );
    return icon.color!;
  }

  testWidgets('healthy tier: localized label + success token icon', (
    tester,
  ) async {
    await pumpPill(
      tester,
      tier: BackendHealthTier.healthy,
      brightness: Brightness.light,
    );
    expect(find.text('Backend ready'), findsOneWidget);
    expect(iconColorOf(tester), DesignTokens.colorSemanticSuccessLight);
    expect(find.byKey(const Key('profile-health-pill')), findsOneWidget);
  });

  testWidgets('degraded tier: localized label + warning token icon', (
    tester,
  ) async {
    await pumpPill(
      tester,
      tier: BackendHealthTier.degraded,
      brightness: Brightness.light,
    );
    expect(find.text('Backend degraded'), findsOneWidget);
    expect(iconColorOf(tester), DesignTokens.colorSemanticWarningLight);
  });

  testWidgets('unhealthy tier: own localized label, error token icon', (
    tester,
  ) async {
    await pumpPill(
      tester,
      tier: BackendHealthTier.unhealthy,
      brightness: Brightness.light,
    );
    expect(find.text('Backend impaired'), findsOneWidget);
    expect(iconColorOf(tester), DesignTokens.colorSemanticErrorLight);
  });

  testWidgets(
    'offline tier: own localized label, error token icon (offline-pill family)',
    (tester) async {
      await pumpPill(
        tester,
        tier: BackendHealthTier.offline,
        brightness: Brightness.light,
      );
      expect(find.text('Backend unreachable'), findsOneWidget);
      expect(iconColorOf(tester), DesignTokens.colorSemanticErrorLight);
    },
  );

  testWidgets('dark mode resolves the DARK token variants', (tester) async {
    await pumpPill(
      tester,
      tier: BackendHealthTier.healthy,
      brightness: Brightness.dark,
    );
    expect(find.text('Backend ready'), findsOneWidget);
    expect(iconColorOf(tester), DesignTokens.colorSemanticSuccessDark);
  });

  testWidgets('no data yet (null): the pill stays empty — no wrong tier', (
    tester,
  ) async {
    await pumpPill(tester, tier: null, brightness: Brightness.light);
    expect(find.byKey(const Key('profile-health-pill')), findsNothing);
    expect(find.text('Backend ready'), findsNothing);
  });

  testWidgets('state is announced via semantics label (never color alone)', (
    tester,
  ) async {
    await pumpPill(
      tester,
      tier: BackendHealthTier.offline,
      brightness: Brightness.light,
    );
    final semantics = tester.widget<Semantics>(
      find.byKey(const Key('profile-health-pill-semantics')),
    );
    expect(semantics.properties.label, 'Backend unreachable');
    // CodeRabbit #662: the child Text's own semantics node is excluded, so
    // the tier is announced ONCE (the wrapper's label), matching OfflinePill.
    expect(semantics.excludeSemantics, isTrue);
  });

  group('goldens (German template locale, AGENTS.md §6)', () {
    for (final tier in BackendHealthTier.values) {
      for (final entry in [
        (Brightness.light, 'light'),
        (Brightness.dark, 'dark'),
      ]) {
        final (brightness, name) = entry;
        testWidgets('${tier.name} $name', (tester) async {
          await pumpPill(
            tester,
            tier: tier,
            brightness: brightness,
            locale: const Locale('de'),
          );
          expect(find.text(_deLabels[tier]!), findsOneWidget);
          expect(iconColorOf(tester), _expectedColor(tier, brightness));
          await expectLater(
            find.byKey(const Key('profile-health-pill')),
            matchesGoldenFile(
              'goldens/backend_health_pill_${tier.name}_$name.png',
            ),
          );
        });
      }
    }
  });

  // Keep the English catalog in the loop so de/en key parity drift cannot
  // slip through the widget layer unnoticed.
  test('de/en label catalogs cover every tier', () {
    expect(_deLabels.keys.toSet(), BackendHealthTier.values.toSet());
    expect(_enLabels.keys.toSet(), BackendHealthTier.values.toSet());
  });
}
