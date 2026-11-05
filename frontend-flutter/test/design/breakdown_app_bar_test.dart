// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// The shared header widget (issue #824): a screen never sizes its own bar, and
// a text title is always one line with an ellipsis — the header can therefore
// never be taller than its spec, and a long scene summary is truncated instead
// of clipped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/components/breakdown_app_bar.dart';
import 'package:frontend_flutter/design/header_metrics.dart';
import 'package:frontend_flutter/design/theme.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(360, 640),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppThemes.light(), home: home));
  }

  Future<void> pump(
    WidgetTester tester,
    PreferredSizeWidget bar, {
    Size size = const Size(360, 640),
  }) async {
    await pumpHome(
      tester,
      Scaffold(appBar: bar, body: const SizedBox.expand()),
      size: size,
    );
  }

  const longTitle =
      'Szene 7 — Nachtdreh am Hafenbecken mit der gesamten Hauptbesetzung und '
      'allen Komparsen, inklusive einer sehr langen Zusammenfassung';

  group('BreakdownAppBar (issue #824)', () {
    testWidgets('the height is the theme role, never a call-site literal', (
      tester,
    ) async {
      await pump(tester, const BreakdownAppBar(title: 'Einstellungen'));
      final appBarTheme = AppThemes.light().appBarTheme;

      expect(
        tester.getSize(find.byType(AppBar)).height,
        appBarTheme.toolbarHeight,
      );
      expect(
        tester.getSize(find.byType(AppBar)).height,
        HeaderMetrics.toolbarHeight,
      );
      // A screen cannot smuggle a different height in: the component's
      // preferredSize matches what the theme renders.
      expect(
        tester
            .widget<BreakdownAppBar>(find.byType(BreakdownAppBar))
            .preferredSize,
        const Size.fromHeight(HeaderMetrics.toolbarHeight),
      );
    });

    testWidgets('a text title is ONE line and ellipsized, not clipped', (
      tester,
    ) async {
      await pump(tester, const BreakdownAppBar(title: longTitle));

      final title = tester.widget<Text>(find.text(longTitle));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(title.softWrap, isFalse);

      // One line of the token line height fits inside the bar (with the
      // derived padding), so nothing overflows the toolbar.
      expect(
        tester.getSize(find.text(longTitle)).height,
        HeaderMetrics.lineHeight,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the title style comes from the theme', (tester) async {
      await pump(tester, const BreakdownAppBar(title: 'Credits'));
      final style = tester.widget<Text>(find.text('Credits')).style;
      // `null` means "inherit the app bar's titleTextStyle" — the theme value
      // is what actually paints the header.
      expect(style, isNull);
      final context = tester.element(find.text('Credits'));
      final resolved = DefaultTextStyle.of(context).style;
      expect(resolved.fontSize, HeaderMetrics.fontSize);
      expect(resolved.fontWeight, HeaderMetrics.fontWeight);
    });

    testWidgets('actions and an explicit leading pass through', (tester) async {
      await pump(
        tester,
        BreakdownAppBar(
          title: 'Import',
          leading: IconButton(
            key: const Key('custom-leading'),
            icon: const Icon(Icons.close),
            onPressed: () {},
          ),
          actions: [
            IconButton(
              key: const Key('custom-action'),
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {},
            ),
          ],
        ),
      );

      expect(find.byKey(const Key('custom-leading')), findsOneWidget);
      expect(find.byKey(const Key('custom-action')), findsOneWidget);
      // An explicit leading replaces the implied back button.
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('automaticallyImplyLeading=false suppresses the back button', (
      tester,
    ) async {
      await pump(
        tester,
        const BreakdownAppBar(
          title: 'Season-Setup',
          automaticallyImplyLeading: false,
        ),
      );
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('a composite title renders verbatim (custom constructor)', (
      tester,
    ) async {
      await pump(
        tester,
        BreakdownAppBar.custom(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 16),
              SizedBox(width: 8),
              Text('KI-Tag'),
            ],
          ),
        ),
      );
      expect(find.text('KI-Tag'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    });

    testWidgets('a long title on a pushed route still pops via the 48dp back '
        'target', (tester) async {
      await pumpHome(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      Scaffold(appBar: const BreakdownAppBar(title: longTitle)),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      final back = find.byType(BackButton);
      expect(back, findsOneWidget);
      expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(back).width, greaterThanOrEqualTo(48));

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text(longTitle), findsNothing);
    });

    testWidgets('the header holds at textScaler 1.3 (a11y ceiling)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
              size: Size(360, 640),
            ),
            child: const Scaffold(
              appBar: BreakdownAppBar(title: 'KI-Konfiguration'),
              body: SizedBox.expand(),
            ),
          ),
        ),
      );

      // 28 dp line × 1.3 = 36.4 dp still fits the 48 dp bar.
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AppBar)).height,
        HeaderMetrics.toolbarHeight,
      );
    });
  });
}
