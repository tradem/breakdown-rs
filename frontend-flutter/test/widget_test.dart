// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

import 'features/seasons/seasons_test_fakes.dart';

void main() {
  testWidgets('App boots at the login gate; Continue renders Seasons', (
    tester,
  ) async {
    // Auth gate (D1, spec `flutter-auth-shell`): dev-auth boots signed out
    // at `LoginScreen` (dev notice + Continue) — the main-app subtree only
    // exists for a resolved session.
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        // Transport is never exercised here (default fetch errs without
        // network); the override satisfies the fail-closed default.
        apiDioProvider.overrideWithValue(Dio()),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byKey(const Key('login-continue-button')), findsOneWidget);
    expect(find.text('Seasons'), findsNothing);

    await tester.tap(find.byKey(const Key('login-continue-button')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // The gate recomposes to the seasons shell (empty projection, no crash).
    expect(find.text('Seasons'), findsOneWidget);
  });
}
