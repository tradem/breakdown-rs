// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/oidc_client.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';

import '../test/auth/oidc_test_fakes.dart';
import '../test/features/seasons/seasons_test_fakes.dart';

/// Login-shell smoke on device (task 3.7, design.md §8 Tier 4).
///
/// - Dev-auth: boot → gate (`LoginScreen` with dev notice) → Continue →
///   seasons render. Dev-auth boots signed out at the gate (spec
///   `flutter-auth-shell`); the permissive session resolves explicitly.
/// - OIDC-fake cold start: a production-shaped (non-dev-auth) build boots
///   to the gate, and a platform failure surfaces as keyed copy — no crash,
///   no main-app subtree. Real OIDC end-to-end (Custom Tabs + IdP) is
///   exercised manually per release against the dev Logto container; the
///   fake covers CI/device farms without an IdP.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dev-auth: boot → gate → continue → seasons render', (
    tester,
  ) async {
    final db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    final holder = ValueNotifier<Result<List<SeasonView>>>(
      Right([season('e2e-1', number: 1, title: 'E2E Season')]),
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const ImmediateReconciliationScheduler(),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(() async => holder.value);
        }),
      ],
    );
    addTearDown(container.dispose);

    // Boot lands at the gate — dev notice, no main-app subtree yet.
    await pumpApp(tester, container);
    expect(find.byKey(const Key('login-dev-notice')), findsOneWidget);
    expect(find.byKey(const Key('login-continue-button')), findsOneWidget);
    expect(find.text('Seasons'), findsNothing);

    // Continue resolves the permissive session; the gate recomposes.
    await tester.tap(find.byKey(const Key('login-continue-button')));
    await tester.pumpAndSettle();

    expect(find.text('Seasons'), findsOneWidget);
    expect(find.byKey(const Key('season-e2e-1')), findsOneWidget);
    expect(find.text('E2E Season'), findsOneWidget);
  });

  testWidgets('oidc-fake cold start: gate renders, failure surfaces keyed', (
    tester,
  ) async {
    final failingUi = FakeAuthorizationUi(
      const Left(ProblemError(code: 'oidc.browser_launch_failed')),
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(realOidcConfig),
        tokenStoreProvider.overrideWithValue(FakeTokenStore(null)),
        oidcClientProvider.overrideWithValue(
          AsyncValue.data(
            Right<ProblemError, OidcClient>(clientFor(failingUi)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Cold start with real-OIDC config: gate renders LoginScreen, and the
    // seasons subtree does not exist (no main-app network calls possible).
    await pumpApp(tester, container);
    expect(find.byKey(const Key('login-signin-button')), findsOneWidget);
    expect(find.byKey(const Key('login-dev-notice')), findsNothing);
    expect(find.byKey(const Key('seasons-list')), findsNothing);

    // A platform failure surfaces as localized copy keyed on `code`.
    await tester.tap(find.byKey(const Key('login-signin-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
    expect(find.textContaining('oidc.browser_launch_failed'), findsOneWidget);
    expect(find.text('Seasons'), findsNothing);
  });
}
