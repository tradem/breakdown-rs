// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget tests for the production overview's active-jobs summary row
// (issue #547): the row is visible exactly while at least one known
// AI-import job needs attention (any non-`succeeded` status — a silent
// `dead_letter` keeps summoning the row), is hidden when everything
// succeeded, and opens the jobs screen. It reads the controller's
// cached state and arms NO watch (D5).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_screen.dart';
import 'package:frontend_flutter/features/shell/production_overview_screen.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../ai_import/jobs_screen_test.dart' show FakeJobsRepository;
import '../seasons/seasons_test_fakes.dart'
    show FakeSeasonRepository, devAuthConfig, season;

import '../../support/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  late CacheDatabase db;
  late FakeSeasonRepository seasonRepo;
  late FakeJobsRepository jobsRepo;
  late ProviderContainer container;

  Future<void> setupContainer({Result<List<AiImportJob>>? jobsResult}) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    seasonRepo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    jobsRepo = FakeJobsRepository(BreakdownApi(), AiImportJobsCacheDao(db))
      ..listResult = jobsResult ?? const Right(<AiImportJob>[]);
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(seasonRepo),
        aiImportRepositoryProvider.overrideWithValue(jobsRepo),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(
            () async => Right([season('season-1', number: 1)]),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  /// Pumps the production overview (issue #610: the AI-import jobs row is
  /// re-homed there from the dissolved Planen destination) for the
  /// container's active season.
  Future<void> pumpProductionOverview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light(),
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ProductionOverviewScreen(season: season('season-1', number: 1)),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('the summary row is visible while a job needs attention '
      '(running) and opens the jobs screen; the tab itself arms no watch', (
    tester,
  ) async {
    await setupContainer(jobsResult: Right([_job('job-1', JobStatus.running)]));
    await pumpProductionOverview(tester);

    expect(find.byKey(const Key('production-active-jobs')), findsOneWidget);
    expect(jobsRepo.watchCalls, 0);
    await tester.tap(find.byKey(const Key('production-active-jobs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AiImportJobsScreen), findsOneWidget);
    await tester.pump();
  });

  testWidgets(
    'a dead_letter job keeps the row visible — the silent '
    'dead-letter hole closes on a cold start back at the production overview',
    (tester) async {
      await setupContainer(
        jobsResult: Right([_job('job-1', JobStatus.deadLetter)]),
      );
      await pumpProductionOverview(tester);
      expect(find.byKey(const Key('production-active-jobs')), findsOneWidget);
      await tester.pump();
    },
  );

  testWidgets('the row is hidden when every job succeeded', (tester) async {
    await setupContainer(
      jobsResult: Right([_job('job-1', JobStatus.succeeded)]),
    );
    await pumpProductionOverview(tester);
    expect(find.byKey(const Key('production-active-jobs')), findsNothing);
    await tester.pump();
  });

  testWidgets('the row is hidden when nothing was ever imported '
      '(no cache rows, empty list)', (tester) async {
    await setupContainer();
    await pumpProductionOverview(tester);
    expect(find.byKey(const Key('production-active-jobs')), findsNothing);
    await tester.pump();
  });
}

AiImportJob _job(String id, JobStatus status) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = status
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);
