// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Issue #705: the cross-block episode-number conflict — the refusal carries
// the conflict's home (season/block) and the apply card offers a one-tap
// scope-switch recovery (bypassing the season-scoped chip picker).
//
// The ensureGroupEpisodeResolved cases are driven through the REAL
// preview-screen seeding path (the screen calls it for every create target):
// a post-frame WidgetRef harness would fight the test zone — the provider
// chain settles across many event-loop turns there, while the production
// path's pump loop (the established `pumpPreview` pattern) flushes it.
// Kept in its own file: preview_apply_test.dart compiles for minutes on a
// cold dev machine; this suite stays small and fast.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/episode_repository.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

/// Mirrors preview_apply_test.dart's dev fixture (dev-auth mode → `signIn`
/// resolves the permissive session without platform channels).
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
  defaultProjectId: 'series-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cross-block episode-number conflict recovery (issue #705)', () {
    late CacheDatabase db;
    late _Fake705EpisodeRepository episodeRepo;
    late _Fake705SeasonRepository seasonRepo;
    late ProviderContainer container;
    late ValueNotifier<Result<AiImportPreviewResponse>> preview;

    /// The script preview with ONE `Ep.: 293` draft-episode group — the
    /// reviewer-facing shape of the #705 report.
    Future<void> setupContainer() async {
      FlutterSecureStoragePlatform.instance = _FakeSecureStorage705();
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      episodeRepo = _Fake705EpisodeRepository(db);
      seasonRepo = _Fake705SeasonRepository(db);
      preview = ValueNotifier(
        Right(
          AiImportPreviewResponse(
            (b) => b
              ..jobId = 'job-1'
              ..documentKind = DocumentKind.schedule
              ..status = JobStatus.succeeded
              ..preview.replace(
                AiPreviewPayload(
                  (b) => b
                    ..oneOf =
                        OneOf.fromValue3<
                          AiPreviewPayloadOneOf,
                          AiPreviewPayloadOneOf1,
                          AiPreviewPayloadOneOf2
                        >(
                          value: AiPreviewPayloadOneOf(
                            (b) => b
                              ..kind = AiPreviewPayloadOneOfKindEnum.script
                              ..data.replace(
                                ScriptContext(
                                  (b) => b
                                    ..title = 'Pilot'
                                    ..scenes.replace(<DraftScene>[
                                      _draft('d1', number: 293),
                                    ])
                                    ..uncertainties.replace(
                                      const <Uncertainty>[],
                                    ),
                                ),
                              ),
                          ),
                        ),
                ),
              ),
          ),
        ),
      );
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(
            AiImportRepository(BreakdownApi(), AiImportJobsCacheDao(db)),
          ),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
          aiPreviewProvider.overrideWith((ref, jobId) async => preview.value),
          episodesListFetchProvider('job-block', 'series-1').overrideWith(
            (ref) async => Right<ProblemError, List<EpisodeView>>(const []),
          ),
          blocksListFetchProvider('series-1').overrideWith(
            (ref) async => Right<ProblemError, List<BlockView>>(const []),
          ),
          episodeRepositoryProvider.overrideWithValue(episodeRepo),
          seasonRepositoryProvider.overrideWithValue(seasonRepo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
      // The block anchor comes from the cached job row (aiJobBlockInfo) —
      // the job was uploaded in Block 4 ("job-block"); the conflicting
      // episode lives elsewhere.
      await AiImportJobsCacheDao(db).upsertWithEpisodeContext(
        _blockBoundJob('job-1'),
        DateTime.utc(2026, 1, 1),
        episodeId: 'ep-1',
        projectId: 'series-1',
      );
    }

    /// Pumps the preview screen and lets the seeding's pump loop flush —
    /// the established `pumpPreview` pattern.
    Future<void> pumpPreview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiPreviewScreen(jobId: 'job-1')),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('the preview seeding refuses a number taken in ANOTHER block '
        'and carries the conflict location in the extensions', (tester) async {
      await setupContainer();
      // Episode 293 lives in Season 2 · Block 3 — not the job's block-4.
      episodeRepo.listBySeriesResult = Right([
        _episodeInBlock('ep-293', 293, 'home-block'),
      ]);
      episodeRepo.blockByIdResult = Right(
        _blockView('home-block', seasonId: 'season-2', number: 3),
      );
      seasonRepo.getResult = Right(
        _seasonView('season-2', number: 2, title: 'Season 2'),
      );
      await pumpPreview(tester);

      final error = container
          .read(aiApplyControllerProvider('job-1'))
          .commandError;
      expect(error?.code, 'ai_import.episode_number_other_block');
      expect(error?.extensions?['existing_episode_id'], 'ep-293');
      expect(error?.extensions?['existing_block_id'], 'home-block');
      expect(error?.extensions?['existing_season_id'], 'season-2');
      expect(error?.extensions?['existing_season_number'], 2);
      expect(error?.extensions?['existing_season_title'], 'Season 2');
      expect(error?.extensions?['existing_block_number'], 3);
    });

    testWidgets('the same number in the JOB block is still adopted (no '
        'regression from the #705 attribution detour)', (tester) async {
      await setupContainer();
      episodeRepo.listBySeriesResult = Right([
        _episodeInBlock('ep-293', 293, 'job-block'),
      ]);
      await pumpPreview(tester);

      final state = container.read(aiApplyControllerProvider('job-1'));
      expect(state.commandError, isNull);
      expect(state.targetFor('ep:293'), isA<ExistingEpisodeGroupTarget>());
    });

    testWidgets('the seeding degrades to ids-only extensions when the '
        'location lookup fails (offline block read)', (tester) async {
      await setupContainer();
      episodeRepo.listBySeriesResult = Right([
        _episodeInBlock('ep-293', 293, 'home-block'),
      ]);
      episodeRepo.blockByIdResult = const Left(
        ProblemError(code: 'transport.connectionError'),
      );
      await pumpPreview(tester);

      final error = container
          .read(aiApplyControllerProvider('job-1'))
          .commandError;
      expect(error?.code, 'ai_import.episode_number_other_block');
      expect(error?.extensions?['existing_block_id'], 'home-block');
      expect(
        error?.extensions?['existing_block_number'],
        isNull,
        reason: 'the copy must fall back to the extension-less narrative',
      );
    });

    test('the refusal copy names season and block; extension-less errors '
        'degrade to the bare narrative', () {
      const resolved = ProblemError(
        code: 'ai_import.episode_number_other_block',
        extensions: {
          'existing_season_number': 2,
          'existing_season_title': 'Staffel Zwei',
          'existing_block_number': 3,
        },
      );
      expect(
        otherBlockCopy(lookupAppLocalizations(const Locale('en')), resolved),
        contains('Staffel Zwei'),
      );
      expect(
        otherBlockCopy(lookupAppLocalizations(const Locale('en')), resolved),
        contains('Block 3'),
      );
      // Without the location the honest bare narrative stays.
      const bare = ProblemError(code: 'ai_import.episode_number_other_block');
      expect(
        otherBlockCopy(lookupAppLocalizations(const Locale('en')), bare),
        contains('different block'),
      );
    });

    test('crossBlockScopeRecovery branches by code and job block', () {
      const crossBlock = ProblemError(
        code: 'ai_import.episode_number_other_block',
        extensions: {'existing_block_id': 'home-block'},
      );
      expect(crossBlockScopeRecovery(crossBlock, jobBlockId: 'job-block'), (
        blockId: 'home-block',
      ));
      // The #665 409: foreign block → the scope switch (assign-existing
      // would 403 at the IDOR gate); same block → assign-existing owns it
      // (null here); unknown job block → no safe recovery.
      const taken = ProblemError(
        code: 'episode.number-already-exists',
        extensions: {'existing_block_id': 'home-block'},
      );
      expect(crossBlockScopeRecovery(taken, jobBlockId: 'job-block'), (
        blockId: 'home-block',
      ));
      const takenSameBlock = ProblemError(
        code: 'episode.number-already-exists',
        extensions: {'existing_block_id': 'job-block'},
      );
      expect(
        crossBlockScopeRecovery(takenSameBlock, jobBlockId: 'job-block'),
        isNull,
      );
      expect(crossBlockScopeRecovery(taken, jobBlockId: null), isNull);
      // Extension-less older backend → no recovery, bare narrative.
      expect(
        crossBlockScopeRecovery(
          const ProblemError(code: 'ai_import.episode_number_other_block'),
          jobBlockId: 'job-block',
        ),
        isNull,
      );
    });

    testWidgets('the scope-switch recovery button switches the sticky scope '
        'and lands on the upload screen', (tester) async {
      await setupContainer();
      episodeRepo.blockByIdResult = Right(
        _blockView('home-block', seasonId: 'season-2', number: 3),
      );
      final blockSub = container.listen(activeBlockProvider, (_, _) {});
      addTearDown(blockSub.close);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiApplySection(jobId: 'job-1')),
        ),
      );
      await tester.pump();

      // Seed the dead-end refusal the way the in-preview resolution does.
      container
          .read(aiApplyControllerProvider('job-1').notifier)
          .setCommandError(
            const ProblemError(
              code: 'ai_import.episode_number_other_block',
              extensions: {
                'existing_episode_id': 'ep-293',
                'existing_block_id': 'home-block',
                'existing_season_number': 2,
                'existing_block_number': 3,
              },
            ),
          );
      await tester.pump();

      expect(find.byKey(const Key('ai-apply-switch-scope')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-apply-switch-scope')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      // The sticky scope switched to the episode's home season+block —
      // the switch bypasses the season-scoped chip picker (AC3).
      final scope = container.read(activeBlockProvider);
      expect(scope?.seasonId, 'season-2');
      expect(scope?.blockId, 'home-block');
      expect(scope?.blockNumber, 3);
      // The dead-end refusal is dismissed…
      expect(
        container.read(aiApplyControllerProvider('job-1')).commandError,
        isNull,
      );
      // …and the reviewer lands on the re-upload screen.
      expect(find.byKey(const Key('ai-import-submit-screen')), findsOneWidget);
    });

    testWidgets('a cross-block 409 uses the CACHED JOB ROW block (not the '
        'possibly block-less context) to gate the recovery buttons', (
      tester,
    ) async {
      await setupContainer();
      final blockSub = container.listen(activeBlockProvider, (_, _) {});
      addTearDown(blockSub.close);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiApplySection(jobId: 'job-1')),
        ),
      );
      // The group the 409 is about: the draft's `Ep.: 293` marker seeds the
      // create-293 default (a block-less context — the picker path).
      container.read(aiApplyControllerProvider('job-1').notifier).seedRows([
        PreviewRow(draftRef: 'd1', label: 'A', episode: _epMeta293()),
      ], const AiJobContext(episodeId: 'ep-1', projectId: 'series-1'));
      // Seed the #665 409 the backend answers for a create number taken by
      // an episode in a FOREIGN block. The apply context carries no blockId
      // (the missing-context picker drops it) — the job row's block anchor
      // must own the comparison (CodeRabbit review).
      container
          .read(aiApplyControllerProvider('job-1').notifier)
          .setCommandError(
            const ProblemError(
              code: 'episode.number-already-exists',
              status: 409,
              extensions: {
                'existing_episode_id': 'ep-293',
                'number': 293,
                'existing_block_id': 'home-block',
              },
            ),
          );
      // Pump until the cached job-block provider settles.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      // Foreign block → the scope-switch recovery, NOT the assign-existing
      // tap that would 403 at the IDOR gate.
      expect(find.byKey(const Key('ai-apply-switch-scope')), findsOneWidget);
      expect(
        find.byKey(const Key('ai-apply-assign-existing-instead')),
        findsNothing,
      );
    });

    testWidgets('a same-block 409 keeps the #665 assign-existing tap and '
        'shows no scope switch', (tester) async {
      await setupContainer();
      final blockSub = container.listen(activeBlockProvider, (_, _) {});
      addTearDown(blockSub.close);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiApplySection(jobId: 'job-1')),
        ),
      );
      container.read(aiApplyControllerProvider('job-1').notifier).seedRows([
        PreviewRow(draftRef: 'd1', label: 'A', episode: _epMeta293()),
      ], const AiJobContext(episodeId: 'ep-1', projectId: 'series-1'));
      container
          .read(aiApplyControllerProvider('job-1').notifier)
          .setCommandError(
            const ProblemError(
              code: 'episode.number-already-exists',
              status: 409,
              extensions: {
                'existing_episode_id': 'ep-293',
                'number': 293,
                'existing_block_id': 'job-block',
              },
            ),
          );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        find.byKey(const Key('ai-apply-assign-existing-instead')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-apply-switch-scope')), findsNothing);
    });
  });
}

// --- Fixtures ----------------------------------------------------------------

/// The `Ep.: 293` marker metadata a draft row carries (issue #581) — seeds
/// the create-293 group default the 409s are about.
DraftEpisode _epMeta293() => DraftEpisode(
  (b) => b
    ..number = 293
    ..title = 'Neustart',
);

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

/// A job DTO bound to a block (the #705 shape — the block anchor drives
/// `aiJobBlockInfoProvider` and thus the in-preview episode resolution).
AiImportJob _blockBoundJob(String id) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..blockId = 'job-block'
    ..status = JobStatus.succeeded
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

DraftScene _draft(String ref, {int? number}) => DraftScene((b) {
  b
    ..draftRef = ref
    ..sceneNumber = number
    ..summary = 'Scene $ref'
    ..characters.replace(const <DraftCharacter>[])
    ..costumes.replace(const <DraftCostume>[])
    ..episode.replace(
      DraftEpisode(
        (b) => b
          ..number = number
          ..title = 'Neustart',
      ),
    );
});

EpisodeView _episodeInBlock(String id, int number, String blockId) =>
    EpisodeView(
      (b) => b
        ..id = id
        ..blockId = blockId
        ..number = number
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

BlockView _blockView(String id, {required String seasonId, int number = 3}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..projectId = 'series-1'
        ..seasonId = seasonId
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

SeasonView _seasonView(String id, {required int number, String? title}) =>
    SeasonView(
      (b) => b
        ..id = id
        ..number = number
        ..projectId = 'series-1'
        ..archived = false
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1
        ..title = title,
    );

/// Episode-repo fake scripting [blockById] and [listBySeries] — the two
/// reads `ensureGroupEpisodeResolved` and the #705 recovery perform.
class _Fake705EpisodeRepository extends EpisodeRepository {
  _Fake705EpisodeRepository(CacheDatabase db)
    : super(BreakdownApi(), EpisodeCacheDao(db));

  Result<List<EpisodeView>>? listBySeriesResult;

  Result<BlockView>? blockByIdResult;

  @override
  Future<Result<List<EpisodeView>>> listBySeries(
    String projectId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async =>
      listBySeriesResult ?? const Right<ProblemError, List<EpisodeView>>([]);

  @override
  Future<Result<BlockView>> blockById(String id) async =>
      blockByIdResult ??
      Right<ProblemError, BlockView>(_blockView(id, seasonId: 'season-1'));
}

/// Season-repo fake scripting [get] — the label resolution reads the season
/// once for the refusal copy.
class _Fake705SeasonRepository extends SeasonRepository {
  _Fake705SeasonRepository(CacheDatabase db)
    : super(BreakdownApi(), SeasonCacheDao(db));

  Result<SeasonView>? getResult;

  @override
  Future<Result<SeasonView>> get(String id) async =>
      getResult ?? Right<ProblemError, SeasonView>(_seasonView(id, number: 1));
}

/// Minimal secure-storage platform fake: the scope switch persists
/// fire-and-forget; without a platform fake the unawaited write would
/// surface a MissingPluginException as an unhandled async error.
class _FakeSecureStorage705 extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }
}
