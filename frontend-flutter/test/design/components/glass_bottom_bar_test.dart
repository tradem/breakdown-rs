// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/components/glass_bottom_bar.dart';
import 'package:frontend_flutter/design/navigation_bar_metrics.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/shell/app_shell.dart';
import 'package:frontend_flutter/l10n/app_localizations_delegates.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_de.dart';

/// The compact morphology's glass bar surface (issue #991).
///
/// Structure is asserted here (blur present, tint resolved from the theme, the
/// keyboard fallback dropping the filter); the *visual* proof — content
/// actually blurred through the bar — lives in the two goldens, because a
/// widget assertion cannot see a shader result (issue #991 risk 4: no
/// wall-clock, no shader-dependent assertions).
void main() {
  /// The bar the shell renders in its compact slot.
  Widget bar() => GlassBottomBar(
    child: ShellDestinations.navigationBar(
      selectedIndex: 0,
      onSelected: (_) {},
      l10n: AppLocalizationsDe(),
    ),
  );

  /// Content that visibly changes color under the bar, so the golden shows the
  /// blur instead of a flat tint (issue #991 risk 3: an empty destination
  /// silently under-tests the effect).
  Widget content(ScrollController controller) => ListView.builder(
    key: const Key('glass-golden-content'),
    controller: controller,
    itemExtent: 48,
    itemCount: 40,
    itemBuilder: (context, index) {
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final Color color = switch (index % 3) {
        0 => scheme.primaryContainer,
        1 => scheme.tertiaryContainer,
        _ => scheme.errorContainer,
      };
      return ColoredBox(color: color);
    },
  );

  Future<ScrollController> pumpBar(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
    double keyboardInset = 0,
    double heightDp = 480,
  }) async {
    tester.view.physicalSize = Size(360, heightDp);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ScrollController controller = ScrollController(
      // A fixed offset puts a color boundary directly under the bar: the
      // scrolled-under content is what the blur acts on.
      initialScrollOffset: 120,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.light(),
        darkTheme: AppThemes.dark(),
        themeMode: mode,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MediaQuery(
          // The keyboard fallback is driven by the bottom VIEW INSET.
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: Scaffold(
            extendBody: true,
            body: content(controller),
            bottomNavigationBar: bar(),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  group('glass structure', () {
    testWidgets('the bar sits behind a clipped BackdropFilter', (tester) async {
      await pumpBar(tester);
      expect(find.byType(GlassBottomBar), findsOneWidget);
      expect(find.byType(ClipRect), findsWidgets);
      expect(find.byType(BackdropFilter), findsOneWidget);
      // The bar itself is untouched: same widget, same keys, same destinations.
      expect(find.byKey(const Key('shell-navigation-bar')), findsOneWidget);
      expect(find.byKey(const Key('shell-destination-0')), findsOneWidget);
    });

    testWidgets('the bar paints the translucent tint, nothing opaque', (
      tester,
    ) async {
      await pumpBar(tester);
      final ColorScheme scheme = AppThemes.light().colorScheme;
      final Material material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const Key('shell-navigation-bar')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, NavigationBarMetrics.tint(scheme));
      expect(material.color!.a, lessThan(1));
      expect(material.elevation, 0);
    });

    testWidgets('an open keyboard makes the plane opaque and drops the blur', (
      tester,
    ) async {
      await pumpBar(tester, keyboardInset: 300);
      expect(find.byType(BackdropFilter), findsNothing);
      final ColorScheme scheme = AppThemes.light().colorScheme;
      final Iterable<ColoredBox> planes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      expect(
        planes.any((box) => box.color == NavigationBarMetrics.plane(scheme)),
        isTrue,
      );
      // Same bar, same semantics — only the surface state changed.
      expect(find.byKey(const Key('shell-navigation-bar')), findsOneWidget);
    });
  });

  group('glass goldens (content scrolled under the bar)', () {
    for (final (name, mode) in [
      ('light', ThemeMode.light),
      ('dark', ThemeMode.dark),
    ]) {
      testWidgets('glass over scrolled content — $name', (tester) async {
        await pumpBar(tester, mode: mode);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/glass_bottom_bar_$name.png'),
        );
      });
    }
  });
}
