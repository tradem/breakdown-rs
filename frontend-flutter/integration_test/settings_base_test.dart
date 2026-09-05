// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

import '../test/features/seasons/seasons_test_fakes.dart';

/// Runtime backend-switch smoke on device (task 6.7, design.md §8 Tier 4):
/// change the base to an unreachable URI → the affected screen surfaces the
/// transport failure (stale banner over retained rows) → reset recovers.
///
/// `http://10.0.2.2:9` is the emulator loopback with a refused port: a
/// valid dev URI (loopback http) whose fetch fails fast and
/// deterministically with `transport.*` — no timeout budget involved.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unreachable base surfaces transport error; reset recovers', (
    tester,
  ) async {
    final db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    final holder = ValueNotifier<Result<List<SeasonView>>>(
      Right([season('e2e-1', number: 1, title: 'E2E Season')]),
    );
    var useRealFetch = false;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        tokenStoreProvider.overrideWithValue(FakeTokenStore(null)),
        pinnedSecurityContextProvider.overrideWithValue(SecurityContext()),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const ImmediateReconciliationScheduler(),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          if (useRealFetch) {
            return r.fetchAndCacheList(() async {
              final one = await r.get('x');
              return one.match(
                (e) => Left<ProblemError, List<SeasonView>>(e),
                (_) => const Right<ProblemError, List<SeasonView>>([]),
              );
            });
          }
          return r.fetchAndCacheList(() async => holder.value);
        }),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Future<void> frames({int n = 8}) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> openSettings() async {
      await tester.tap(find.byKey(const Key('seasons-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-settings')));
      await frames();
    }

    // Boot → gate → continue → seeded seasons render, no banner.
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-continue-button')));
    await tester.pumpAndSettle();
    expect(find.text('E2E Season'), findsOneWidget);
    // The retained snapshot (`prevRows`) seeds from an unawaited cache
    // read that can lose the race against the initial fetch write; force
    // a deterministic reseed (bounded state polling, no wall-clock
    // gating) so the post-switch failure has rows to go stale over.
    container.invalidate(seasonsViewControllerProvider);
    for (var i = 0; i < 20; i++) {
      if (container.read(seasonsPrevRowsProvider).isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(container.read(seasonsPrevRowsProvider), isNotEmpty);
    expect(find.byKey(const Key('seasons-stale-banner')), findsNothing);

    // Switch to the unreachable base: dialog closes…
    useRealFetch = true;
    await openSettings();
    await tester.enterText(
      find.byKey(const Key('settings-uri-field')),
      'http://10.0.2.2:9',
    );
    await tester.tap(find.byKey(const Key('settings-save')));
    await frames(n: 12);
    expect(find.byKey(const Key('settings-dialog')), findsNothing);

    // …and the failed refetch surfaces: retained rows + stale banner.
    expect(find.text('E2E Season'), findsOneWidget);
    expect(find.byKey(const Key('seasons-stale-banner')), findsOneWidget);

    // Reset recovers: holder fetch succeeds, banner gone.
    useRealFetch = false;
    await openSettings();
    await tester.tap(find.byKey(const Key('settings-reset')));
    await frames(n: 12);
    expect(find.text('E2E Season'), findsOneWidget);
    expect(find.byKey(const Key('seasons-stale-banner')), findsNothing);
  });
}
