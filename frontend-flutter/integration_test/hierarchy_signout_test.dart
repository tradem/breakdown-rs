// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/auth/login_screen.dart';
import 'package:frontend_flutter/features/auth/sign_out.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-e2e'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _block() => BlockView(
  (b) => b
    ..id = 'block-1'
    ..number = 1
    ..seasonId = 'season-1'
    ..seriesId = 'series-e2e'
    ..startDate = '2026-01-01'
    ..endDate = '2026-01-31'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Immediate scheduler so no backoff is ever awaited on-device.
class _E2eScheduler extends ReconciliationScheduler {
  const _E2eScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const devConfig = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.2.2:3000',
    oidcIss: '',
    devAuthSub: 'dev-e2e',
    oidcAudience: '',
    oidcClientId: '',
    oidcRedirectUri: '',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
    defaultSeriesId: 'series-e2e',
  );

  testWidgets('Sign-out mid-navigation returns to the login gate', (
    tester,
  ) async {
    final db = CacheDatabase();
    addTearDown(db.close);
    final seasonsHolder = ValueNotifier<Result<List<SeasonView>>>(
      Right([_season()]),
    );
    final blocksHolder = ValueNotifier<Result<List<BlockView>>>(
      Right([_block()]),
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(
          SeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
        ),
        blockRepositoryProvider.overrideWithValue(
          BlockRepository(BreakdownApi(), BlockCacheDao(db)),
        ),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const _E2eScheduler(),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final dao = SeasonCacheDao(ref.watch(cacheDatabaseProvider));
          return seasonsHolder.value.match(
            (err) => Left<ProblemError, List<SeasonView>>(err),
            (rows) async {
              await dao.applySnapshot(rows, DateTime.utc(2026, 1, 1));
              return Right<ProblemError, List<SeasonView>>(rows);
            },
          );
        }),
        blocksListFetchProvider('season-1').overrideWith((ref) async {
          final dao = BlockCacheDao(ref.watch(cacheDatabaseProvider));
          return blocksHolder.value.match(
            (err) => Left<ProblemError, List<BlockView>>(err),
            (rows) async {
              await dao.applySnapshotForSeason(
                'season-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<BlockView>>(rows);
            },
          );
        }),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(
            SeasonMembershipDto(
              (b) => b
                ..seasonId = 'season-1'
                ..hasActiveCostumeRoleInSeason = true
                ..capabilities.replace(const ['upload_continuity_photos']),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SeasonsScreen), findsOneWidget);

    // Navigate deep into the hierarchy.
    await tester.tap(find.byKey(const Key('season-season-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BlocksScreen), findsOneWidget);

    // Sign out mid-navigation: the gate swaps the whole subtree to login.
    await container.read(sessionResetProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(BlocksScreen), findsNothing);
    expect(find.byType(SeasonsScreen), findsNothing);
  });
}
