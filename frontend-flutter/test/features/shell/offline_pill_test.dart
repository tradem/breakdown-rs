// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Widget tests (issue #654): the offline pill's two branches — visible on
// offline/degraded, hidden on online — with semantic finders (find.text)
// and the live-region announcement. The connectivity controller runs for
// real against overridden seams (fake passive stream, fake probe, recorded
// delays): no plugin channel, no sleeps, no wall-clock timing.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/features/shell/offline_pill.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/src/connectivity/connectivity_providers.dart';

final class FakePassiveSource implements PassiveConnectivitySource {
  final controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;

  void emit(List<ConnectivityResult> results) => controller.add(results);
}

void main() {
  late FakePassiveSource source;

  Future<void> pumpPill(
    WidgetTester tester, {
    // Optional probe outcome for reconnection scenarios; the default never
    // resolves (unconfirmed reconnection → pill stays visible).
    Future<bool> Function()? probe,
  }) async {
    source = FakePassiveSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          passiveConnectivitySourceProvider.overrideWithValue(source),
          connectivityHttpProbeProvider.overrideWithValue(
            probe ?? (() => Completer<bool>().future),
          ),
          connectivityDelayProvider.overrideWithValue(
            (duration) => Completer<void>().future,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: OfflinePill()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pumps one passive event plus the settle frames the [AnimatedSize]
  /// transition needs (deterministic frame pump, no real time gating).
  Future<void> emitAndSettle(
    WidgetTester tester,
    List<ConnectivityResult> results,
  ) async {
    source.emit(results);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'pill is hidden while online and shows the localized label when offline',
    (tester) async {
      await pumpPill(tester);
      expect(find.text('Offline — data may be stale'), findsNothing);

      await emitAndSettle(tester, [ConnectivityResult.none]);

      expect(find.text('Offline — data may be stale'), findsOneWidget);
      expect(find.byKey(const Key('shell-offline-pill')), findsOneWidget);
    },
  );

  testWidgets(
    'confirmed reconnection hides the pill automatically (no interaction)',
    (tester) async {
      await pumpPill(tester, probe: () async => true);
      await emitAndSettle(tester, [ConnectivityResult.none]);
      expect(find.text('Offline — data may be stale'), findsOneWidget);

      // Carrier returns and the confirmation probe succeeds: the pill hides
      // without user interaction (CodeRabbit #660: this branch was previously
      // only asserted at controller level, never in a rendered tree).
      await emitAndSettle(tester, [ConnectivityResult.wifi]);
      expect(find.text('Offline — data may be stale'), findsNothing);
    },
  );

  testWidgets('unconfirmed reconnection keeps the pill visible (degraded)', (
    tester,
  ) async {
    await pumpPill(tester); // default probe never resolves
    await emitAndSettle(tester, [ConnectivityResult.none]);
    expect(find.text('Offline — data may be stale'), findsOneWidget);

    await emitAndSettle(tester, [ConnectivityResult.wifi]);
    // OS carrier present, probe still unresolved → degraded, pill stays.
    expect(find.text('Offline — data may be stale'), findsOneWidget);
  });

  testWidgets(
    'pill color comes from the theme error container role (no hardcoded colors)',
    (tester) async {
      await pumpPill(tester);
      await emitAndSettle(tester, [ConnectivityResult.none]);

      final context = tester.element(find.text('Offline — data may be stale'));
      final scheme = Theme.of(context).colorScheme;
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('Offline — data may be stale'),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, scheme.errorContainer);
    },
  );

  testWidgets('pill announces itself as a semantics live region', (
    tester,
  ) async {
    await pumpPill(tester);
    await emitAndSettle(tester, [ConnectivityResult.none]);

    final semantics = tester.widget<Semantics>(
      find.byKey(const Key('shell-offline-pill-semantics')),
    );
    expect(semantics.properties.liveRegion, isTrue);
  });
}
