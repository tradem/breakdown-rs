// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Widget tests for the apply episode picker (live-fetch quick fix): the
// picker lists the JOB'S BLOCK episodes from the live read API — never
// only what the user happened to have cached — with the offline-first
// fallback to the block's cached rows on a failed fetch, the error
// branch on a failure with an empty cache, and the legacy cache-wide
// fallback for a job without a block scope.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_screen.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';

// --- Fixtures ---------------------------------------------------------------

const devAuthConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: 'series-1',
);

AiImportJob _job(String id, {String? blockId}) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = JobStatus.succeeded
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..blockId = blockId,
);

EpisodeView _episode(String id, String blockId, {int number = 1}) =>
    EpisodeView(
      (b) => b
        ..id = id
        ..blockId = blockId
        ..number = number
        ..seriesId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

// --- Harness ----------------------------------------------------------------

class Harness {
  Harness({bool failingCacheRead = false}) {
    db = CacheDatabase(NativeDatabase.memory());
    dao = AiImportJobsCacheDao(db);
    episodes = EpisodeCacheDao(db);
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiImportRepositoryProvider.overrideWithValue(
          failingCacheRead
              ? _FailingCacheReadRepository(dao)
              : AiImportRepository(BreakdownApi(), dao),
        ),
        cacheDatabaseProvider.overrideWithValue(db),
        episodesListFetchProvider.overrideWith((ref, params) async {
          final (blockId, _) = params;
          fetchedBlocks.add(blockId);
          return fetchResult;
        }),
      ],
    );
  }

  late final CacheDatabase db;
  late final AiImportJobsCacheDao dao;
  late final EpisodeCacheDao episodes;
  late final ProviderContainer container;

  /// The block ids the picker's fetch seam was called with, in order.
  final List<String> fetchedBlocks = [];

  Result<List<EpisodeView>> fetchResult = const Left(
    ProblemError(code: 'transport.connectionTimeout'),
  );

  Future<void> signIn() =>
      container.read(authSessionControllerProvider.notifier).signIn();

  void dispose() {
    container.dispose();
    db.close();
  }

  /// Pumps a minimal host screen whose button opens the picker for
  /// [jobId], then taps it and settles the sheet.
  Future<void> openPicker(WidgetTester tester, String jobId) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showEpisodePicker(context, ref, jobId),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

// --- Tests ------------------------------------------------------------------

void main() {
  testWidgets('live fetch: the job block\'s episodes from the READ API, '
      'not the cache — a fresh install can assign its episode', (tester) async {
    final h = Harness()..fetchResult = Right([_episode('ep-1', 'b-1')]);
    addTearDown(h.dispose);
    await h.signIn();
    await h.dao.upsertAll([_job('job-1', blockId: 'b-1')], DateTime.utc(2026));

    await h.openPicker(tester, 'job-1');

    // The fetch was SCOPED to the job's block.
    expect(h.fetchedBlocks, ['b-1']);
    // The live row renders even though the episode cache is EMPTY.
    expect(find.byKey(const Key('ai-episode-pick-ep-1')), findsOneWidget);
    // Picking pops the sheet with the episode (the apply payload).
    await tester.tap(find.byKey(const Key('ai-episode-pick-ep-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-episode-picker')), findsNothing);
  });

  testWidgets('fetch failure falls back to the block\'s CACHED rows '
      '(offline-first — a transient failure is never an empty list)', (
    tester,
  ) async {
    final h = Harness(); // fetch stays Left
    addTearDown(h.dispose);
    await h.signIn();
    await h.dao.upsertAll([_job('job-1', blockId: 'b-1')], DateTime.utc(2026));
    await h.episodes.applySnapshotForBlock('b-1', [
      _episode('ep-cached', 'b-1', number: 2),
    ], DateTime.utc(2026));

    await h.openPicker(tester, 'job-1');

    expect(find.byKey(const Key('ai-episode-pick-ep-cached')), findsOneWidget);
    expect(find.byKey(const Key('ai-episode-picker-error')), findsNothing);
  });

  testWidgets('fetch failure with an EMPTY cache surfaces the error branch', (
    tester,
  ) async {
    final h = Harness()
      ..fetchResult = const Left(
        ProblemError(code: 'transport.connectionTimeout'),
      );
    addTearDown(h.dispose);
    await h.signIn();
    await h.dao.upsertAll([_job('job-1', blockId: 'b-1')], DateTime.utc(2026));

    await h.openPicker(tester, 'job-1');

    expect(find.byKey(const Key('ai-episode-picker-error')), findsOneWidget);
  });

  testWidgets('a job WITHOUT a block scope falls back to the cache-wide '
      'read (older-build job id) — and never hits the fetch seam', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await h.signIn();
    await h.dao.upsertAll([_job('job-1')], DateTime.utc(2026));
    await h.episodes.applySnapshotForBlock('b-other', [
      _episode('ep-legacy', 'b-other'),
    ], DateTime.utc(2026));

    await h.openPicker(tester, 'job-1');

    expect(h.fetchedBlocks, isEmpty);
    expect(find.byKey(const Key('ai-episode-pick-ep-legacy')), findsOneWidget);
  });

  testWidgets('a FAILED job-cache read is a picker ERROR — never the '
      'cache-wide fallback (no cross-block episode can be picked)', (
    tester,
  ) async {
    final h = Harness(failingCacheRead: true);
    addTearDown(h.dispose);
    await h.signIn();
    await h.dao.upsertAll([_job('job-1', blockId: 'b-1')], DateTime.utc(2026));
    // Rows that a WRONG cache-wide fallback would happily offer: the
    // error must win instead.
    await h.episodes.applySnapshotForBlock('b-1', [
      _episode('ep-own', 'b-1'),
    ], DateTime.utc(2026));
    await h.episodes.applySnapshotForBlock('b-other', [
      _episode('ep-foreign', 'b-other'),
    ], DateTime.utc(2026));

    await h.openPicker(tester, 'job-1');

    expect(find.byKey(const Key('ai-episode-picker-error')), findsOneWidget);
    expect(find.byKey(const Key('ai-episode-pick-ep-own')), findsNothing);
    expect(find.byKey(const Key('ai-episode-pick-ep-foreign')), findsNothing);
  });
}

/// Cache read always fails (simulates a Drift/IO failure): pins that the
/// picker surfaces the failure instead of mistaking it for a block-less job.
class _FailingCacheReadRepository extends AiImportRepository {
  _FailingCacheReadRepository(AiImportJobsCacheDao dao)
    : super(BreakdownApi(), dao);

  @override
  Future<Result<List<AiImportJobCacheRow>>> readCached(String sub) async =>
      const Left(ProblemError(code: 'cache.read_failed'));
}
