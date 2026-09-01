// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-e2e'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Repository fake: [create] acks with a server id; the projection starts
/// empty so the optimistic overlay is observable before reconciliation.
class _E2eSeasonRepository extends SeasonRepository {
  _E2eSeasonRepository(super.api, super.cache);

  Result<IdVersionResponse>? createResult;

  @override
  Future<Result<IdVersionResponse>> create(CreateSeasonRequest request) =>
      Future.value(
        createResult ??
            Right<ProblemError, IdVersionResponse>(
              IdVersionResponse(
                (b) => b
                  ..id = 'e2e-new'
                  ..version = 1,
              ),
            ),
      );
}

/// Immediate scheduler so no backoff is ever awaited on-device (deterministic
/// reconciliation without wall-clock gating, AGENTS.md §6).
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
    defaultSeriesId: 'series-e2e',
  );

  testWidgets(
    'SeasonsScreen flow: seed list, create optimistically, reconcile',
    (tester) async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final repo = _E2eSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
      await repo.fetchAndCacheList(
        () async => Right([_season('seed', number: 1, title: 'Seeded')]),
        clock: Clock.fixed(DateTime.utc(2026, 1, 2)),
      );

      final holder = ValueNotifier<Result<List<SeasonView>>>(
        Right([_season('seed', number: 1, title: 'Seeded')]),
      );
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _E2eScheduler(),
          ),
          seasonsListFetchProvider.overrideWith((ref) async {
            final r = ref.watch(seasonRepositoryProvider);
            return r.fetchAndCacheList(() async => holder.value);
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SeasonsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The projected row renders from the Drift cache.
      expect(find.text('Seeded'), findsOneWidget);
      expect(find.byKey(const Key('season-add-fab')), findsOneWidget);

      // Open the form and submit a create command.
      await tester.tap(find.byKey(const Key('season-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('create-number')), '2');
      await tester.enterText(find.byKey(const Key('create-title')), 'Created');
      // Scroll the submit button fully on-screen (partial `ensureVisible`
      // reveals only its leading edge on short viewports).
      for (var i = 0; i < 8; i++) {
        final center = tester.getCenter(find.byKey(const Key('create-submit')));
        if (center.dy <
            tester.view.physicalSize.height / tester.view.devicePixelRatio -
                30) {
          break;
        }
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -60),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('create-submit')));
      // Dispatch + let the sheet close and the (immediate-scheduler)
      // reconciliation pass settle. The overlay row — acknowledged by the
      // POST, not yet projected — remains visible regardless of whether the
      // bounded pass reconciled or exhausted to stale.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Optimistic overlay appears (server-acknowledged, controller state).
      expect(find.byKey(const Key('overlay-e2e-new')), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);

      // The projection catches up (same id) → reconciliation replaces the
      // overlay with the authoritative Drift row.
      holder.value = Right([
        _season('seed', number: 1, title: 'Seeded'),
        _season('e2e-new', number: 2, title: 'Created'),
      ]);
      await container.read(seasonsControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overlay-e2e-new')), findsNothing);
      expect(find.byKey(const Key('season-e2e-new')), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
    },
  );
}
