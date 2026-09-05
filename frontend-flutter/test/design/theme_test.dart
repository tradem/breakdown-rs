// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/theme.dart';

/// Design-token tests (spec `flutter-design-tokens`, tasks 1.1/1.3):
/// scheme brightness, M3, and the system-brightness switch without restart.
/// Golden comparisons (light+dark per surface) land with the 3.6 golden pass.
void main() {
  group('AppThemes', () {
    test('light() is a light M3 scheme', () {
      final theme = AppThemes.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('dark() is a dark M3 scheme from the same seed', () {
      final theme = AppThemes.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
      // Same seed token, different brightness mapping — the pair must differ
      // (otherwise the dark theme would be a no-op alias).
      expect(
        theme.colorScheme.surface,
        isNot(AppThemes.light().colorScheme.surface),
      );
    });
  });

  group('theme pair resolves per platform brightness', () {
    Brightness? probed;

    /// Fresh tree per brightness: `_MediaQueryFromView` caches its data
    /// across `pumpWidget` calls with the same view, so an in-test
    /// light→dark transition cannot be observed in widget tests (framework
    /// behavior). The no-restart switch itself is framework-owned
    /// (`ThemeMode.system`, asserted wired in `app_gate_test.dart`); here
    /// we assert the pair resolves to the right scheme per brightness.
    Future<void> pumpThemed(WidgetTester tester, Brightness platform) async {
      probed = null;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: platform),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: Builder(
              builder: (context) {
                probed = Theme.of(context).brightness;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }

    testWidgets('light platform brightness → light scheme', (tester) async {
      await pumpThemed(tester, Brightness.light);
      expect(probed, Brightness.light);
    });

    testWidgets('dark platform brightness → dark scheme', (tester) async {
      await pumpThemed(tester, Brightness.dark);
      expect(probed, Brightness.dark);
    });
  });
}
