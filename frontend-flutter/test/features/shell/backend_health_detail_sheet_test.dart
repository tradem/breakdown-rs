// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Widget + golden tests (issue #730) for the backend health detail sheet the
// drawer's health pill opens: the aggregate tier line, the per-dependency
// rows (localized, topology-free labels + localized status words), the
// severity ordering, the three explanatory states (pending / offline / no
// entries reported), the merged screen-reader announcements, and the close
// affordance. The controller is frozen per case via overrideWithValue — no
// probe, no timers (deterministic-tests hard rule).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/shell/backend_health_detail_sheet.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/src/health/backend_health_providers.dart';

void main() {
  /// Pumps a minimal app whose only affordance opens the sheet through the
  /// PRODUCTION entrypoint ([showBackendHealthDetailSheet]), so the modal
  /// seam (root navigator hosting) is what the tests exercise.
  Future<void> pumpSheetOpener(
    WidgetTester tester, {
    required BackendHealthSnapshot? snapshot,
    required Brightness brightness,
    Locale locale = const Locale('de'),
  }) async {
    tester.view.physicalSize = const Size(400, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendHealthControllerProvider.overrideWithValue(snapshot),
        ],
        child: MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => ElevatedButton(
                    key: const Key('open-health-detail'),
                    onPressed: () => showBackendHealthDetailSheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Opens the sheet and settles its entrance animation.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-health-detail')));
    await tester.pumpAndSettle();
  }

  const mixedChecks = [
    BackendHealthCheck(
      name: 'postgres',
      status: BackendHealthCheckStatus.healthy,
    ),
    BackendHealthCheck(
      name: 'sierradb',
      status: BackendHealthCheckStatus.unhealthy,
    ),
    BackendHealthCheck(
      name: 'vault',
      status: BackendHealthCheckStatus.degraded,
    ),
    BackendHealthCheck(
      name: 'garage',
      status: BackendHealthCheckStatus.healthy,
    ),
  ];

  testWidgets('aggregate tier line reuses the pill vocabulary', (tester) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(tier: BackendHealthTier.unhealthy),
      brightness: Brightness.light,
    );
    await openSheet(tester);

    expect(
      find.byKey(const Key('backend-health-detail-sheet')),
      findsOneWidget,
    );
    expect(find.text('Backend-Status'), findsOneWidget);
    expect(find.text('Backend gestört'), findsOneWidget);
    final aggregate = tester.widget<Semantics>(
      find.byKey(const Key('backend-health-detail-aggregate-semantics')),
    );
    expect(aggregate.properties.label, 'Backend gestört');
    expect(aggregate.excludeSemantics, isTrue);
  });

  testWidgets(
    'per-dependency rows: functional labels + localized status words',
    (tester) async {
      await pumpSheetOpener(
        tester,
        snapshot: const BackendHealthSnapshot(
          tier: BackendHealthTier.unhealthy,
          checks: mixedChecks,
        ),
        brightness: Brightness.light,
      );
      await openSheet(tester);

      // SectionHeader renders the localized label upper-cased (settings
      // family grouping affordance).
      expect(find.text('Abhängigkeiten'.toUpperCase()), findsOneWidget);
      expect(find.text('Datenbank'), findsOneWidget);
      expect(find.text('Ereignisspeicher'), findsOneWidget);
      expect(find.text('Geheimnisverwaltung'), findsOneWidget);
      expect(find.text('KI-Dateispeicher'), findsOneWidget);
      // The raw wire keys are NEVER rendered (topology-free labels).
      for (final key in ['postgres', 'sierradb', 'vault', 'garage']) {
        expect(find.text(key), findsNothing, reason: 'raw check key leaked');
      }
      // Every row keeps its own key for stable widget tests.
      for (final key in ['postgres', 'sierradb', 'vault', 'garage']) {
        expect(
          find.byKey(Key('backend-health-detail-check-$key')),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('broken dependencies sort ahead of healthy ones', (tester) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(
        tier: BackendHealthTier.unhealthy,
        checks: mixedChecks,
      ),
      brightness: Brightness.light,
    );
    await openSheet(tester);

    double rowY(String name) => tester
        .getTopLeft(find.byKey(Key('backend-health-detail-check-$name')))
        .dy;

    expect(rowY('sierradb'), lessThan(rowY('vault')));
    expect(rowY('vault'), lessThan(rowY('postgres')));
    expect(rowY('postgres'), lessThan(rowY('garage')));
  });

  testWidgets('rows carry one merged announcement (label: status)', (
    tester,
  ) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(
        tier: BackendHealthTier.degraded,
        checks: [
          BackendHealthCheck(
            name: 'vault',
            status: BackendHealthCheckStatus.degraded,
          ),
        ],
      ),
      brightness: Brightness.light,
    );
    await openSheet(tester);

    final semantics = tester.widget<Semantics>(
      find.byKey(const Key('backend-health-detail-check-semantics-vault')),
    );
    expect(semantics.properties.label, 'Geheimnisverwaltung: eingeschränkt');
    expect(semantics.excludeSemantics, isTrue);
  });

  testWidgets('unknown dependency keys fall back to a generic label', (
    tester,
  ) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(
        tier: BackendHealthTier.unhealthy,
        checks: [
          BackendHealthCheck(
            name: 'some_future_store',
            status: BackendHealthCheckStatus.unhealthy,
          ),
        ],
      ),
      brightness: Brightness.light,
    );
    await openSheet(tester);

    expect(find.text('Weitere Abhängigkeit'), findsOneWidget);
    expect(find.text('some_future_store'), findsNothing);
  });

  testWidgets('offline tier: explanatory body, no dependency rows', (
    tester,
  ) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(tier: BackendHealthTier.offline),
      brightness: Brightness.light,
    );
    await openSheet(tester);

    expect(find.text('Backend nicht erreichbar'), findsOneWidget);
    expect(
      find.byKey(const Key('backend-health-detail-offline')),
      findsOneWidget,
    );
    expect(find.text('Abhängigkeiten'), findsNothing);
    expect(find.byKey(const Key('backend-health-detail-empty')), findsNothing);
  });

  testWidgets('reported tier without entries: honest empty body', (
    tester,
  ) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(tier: BackendHealthTier.healthy),
      brightness: Brightness.light,
    );
    await openSheet(tester);

    expect(find.text('Backend bereit'), findsOneWidget);
    expect(
      find.byKey(const Key('backend-health-detail-empty')),
      findsOneWidget,
    );
    expect(find.text('Abhängigkeiten'), findsNothing);
  });

  testWidgets('no data yet: pending body instead of an invented tier', (
    tester,
  ) async {
    await pumpSheetOpener(tester, snapshot: null, brightness: Brightness.light);
    await openSheet(tester);

    expect(
      find.byKey(const Key('backend-health-detail-pending')),
      findsOneWidget,
    );
    expect(find.text('Status wird abgefragt …'), findsOneWidget);
  });

  testWidgets('the close affordance dismisses the sheet', (tester) async {
    await pumpSheetOpener(
      tester,
      snapshot: const BackendHealthSnapshot(
        tier: BackendHealthTier.unhealthy,
        checks: mixedChecks,
      ),
      brightness: Brightness.light,
    );
    await openSheet(tester);
    expect(
      find.byKey(const Key('backend-health-detail-sheet')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('backend-health-detail-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend-health-detail-sheet')), findsNothing);
    expect(find.byKey(const Key('open-health-detail')), findsOneWidget);
  });

  group('goldens (German template locale, AGENTS.md §6)', () {
    for (final entry in [
      (Brightness.light, 'light'),
      (Brightness.dark, 'dark'),
    ]) {
      final (brightness, name) = entry;
      testWidgets('unhealthy with dependencies $name', (tester) async {
        await pumpSheetOpener(
          tester,
          snapshot: const BackendHealthSnapshot(
            tier: BackendHealthTier.unhealthy,
            checks: mixedChecks,
          ),
          brightness: brightness,
        );
        await openSheet(tester);
        final unhealthyColor = brightness == Brightness.light
            ? DesignTokens.colorSemanticErrorLight
            : DesignTokens.colorSemanticErrorDark;
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: find.byKey(
                    const Key('backend-health-detail-check-sierradb'),
                  ),
                  matching: find.byType(Icon),
                ),
              )
              .color,
          unhealthyColor,
        );
        await expectLater(
          find.byKey(const Key('backend-health-detail-sheet')),
          matchesGoldenFile('goldens/backend_health_detail_checks_$name.png'),
        );
      });

      testWidgets('offline body $name', (tester) async {
        await pumpSheetOpener(
          tester,
          snapshot: const BackendHealthSnapshot(
            tier: BackendHealthTier.offline,
          ),
          brightness: brightness,
        );
        await openSheet(tester);
        await expectLater(
          find.byKey(const Key('backend-health-detail-sheet')),
          matchesGoldenFile('goldens/backend_health_detail_offline_$name.png'),
        );
      });
    }
  });
}
