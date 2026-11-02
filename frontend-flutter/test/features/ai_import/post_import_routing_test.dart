// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Issue #759 — post-apply routing and refresh.
//
// Tier 1: the pure target choice (`pickAppliedTargetEpisode`) and the shared
// outcome copy.
//
// Tier 2: the apply card's success path leaves the review screen for the Script
// destination with the imported episode in scope, publishes the report the
// destination renders (so `unapplied_outfits` and the additional episodes of a
// multi-episode import survive the navigation), re-arms the scene and
// season-script seams (asserted through counting overrides — the AC's
// "provider observers/overrides"), and stays on the review screen with an
// honest hint when the destination cannot be resolved.
//
// Nothing here sleeps: the reconciliation scheduler ticks immediately and the
// apply-run stream is a controllable, silent controller.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/post_import_report.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/scenes/season_script_controller.dart';
import 'package:frontend_flutter/features/shell/script_tab_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

import '../../support/fake_secure_storage.dart';
import '../seasons/seasons_test_fakes.dart' show devAuthConfig, season;

const _jobId = 'job-1';
const _seasonId = 'season-1';
const _blockId = 'block-1';
const _episodeId = 'ep-1';
const _otherEpisodeId = 'ep-2';

AppliedEpisode _appliedEpisode(
  String id, {
  required int count,
  int? number,
  String? name,
}) => AppliedEpisode(
  (b) => b
    ..id = id
    ..appliedCount = count
    ..number = number
    ..name = name,
);

UnappliedOutfit _unappliedOutfit({int ordinal = 2}) => UnappliedOutfit(
  (b) => b
    ..draftRef = 'draft-1'
    ..ordinal = ordinal
    ..characterName = 'Karl'
    ..name = 'Mantel'
    ..reason = UnappliedOutfitReason.pieceRejected,
);

ApplyAiImportResponse _outcome({
  required List<AppliedEpisode> appliedEpisodes,
  List<UnappliedOutfit> unappliedOutfits = const [],
}) => ApplyAiImportResponse(
  (b) => b
    ..appliedCount = appliedEpisodes.fold<int>(
      0,
      (sum, e) => sum + e.appliedCount,
    )
    ..createdDays = 1
    ..plannedSceneShoots = 3
    ..createdCharacters = 0
    ..createdPieces = 0
    ..createdOutfits = 0
    ..createdEpisodes = 0
    ..appliedEpisodes.replace(appliedEpisodes)
    ..unappliedOutfits.replace(unappliedOutfits),
);

AiPreviewPayload _scriptPayload() => AiPreviewPayload(
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
                    ..title = '299 Erlösung'
                    ..scenes.replace([
                      DraftScene(
                        (b) => b
                          ..draftRef = 'draft-1'
                          ..sceneNumber = 1
                          ..summary = 'Szene 1'
                          ..characters.replace(const <DraftCharacter>[])
                          ..outfits.replace(const <DraftOutfit>[]),
                      ),
                      DraftScene(
                        (b) => b
                          ..draftRef = 'draft-2'
                          ..sceneNumber = 2
                          ..summary = 'Szene 2'
                          ..characters.replace(const <DraftCharacter>[])
                          ..outfits.replace(const <DraftOutfit>[]),
                      ),
                    ])
                    ..uncertainties.replace(const <Uncertainty>[]),
                ),
              ),
          ),
        ),
);

AiImportPreviewResponse _previewResponse() => AiImportPreviewResponse(
  (b) => b
    ..jobId = _jobId
    ..documentKind = DocumentKind.script
    ..status = JobStatus.succeeded
    ..preview.replace(_scriptPayload()),
);

AiImportJob _succeededJob() => AiImportJob(
  (b) => b
    ..id = _jobId
    ..userId = 'dev-user'
    ..status = JobStatus.succeeded
    ..documentKind = DocumentKind.script
    ..sourceFormat = SourceFormat.pdf
    ..dedupKey = 'dedup-$_jobId'
    ..documentDigest = 'digest-$_jobId'
    ..sourceHandle = 'handle-$_jobId'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

class _FakeAiImportRepository extends AiImportRepository {
  _FakeAiImportRepository(super.api, super.cache);

  final List<Result<ApplyAiImportResponse>> applyQueue = [];

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async => applyQueue.removeAt(0);
}

/// Season repository whose cache read is scripted (the post-apply resolution
/// reads the import's season from the cache, never from the network).
class _ScriptedSeasonRepository extends SeasonRepository {
  _ScriptedSeasonRepository(super.api, super.cache, this.rows);

  final List<SeasonView> rows;

  @override
  Future<Result<List<SeasonView>>> readCached() async => Right(rows);
}

/// Pumps a bounded number of frames — never `pumpAndSettle` (the Script body
/// renders an indeterminate progress indicator while its composition loads, and
/// an indeterminate animation never settles).
Future<void> pumpFrames(
  WidgetTester tester, {
  int n = 12,
  int stepMs = 25,
}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pickAppliedTargetEpisode (issue #759)', () {
    test('the reviewer-targeted episode wins over the biggest one', () {
      final choice = pickAppliedTargetEpisode([
        _appliedEpisode(_otherEpisodeId, count: 40, number: 298),
        _appliedEpisode(_episodeId, count: 7, number: 299),
      ], requestEpisodeId: _episodeId);

      expect(choice, isNotNull);
      expect(choice!.target.id, _episodeId);
      // The other target is still NAMED — the destination reports it instead
      // of letting the episode scope hide it.
      expect(choice.others.map((e) => e.id), [_otherEpisodeId]);
    });

    test('without a listed target the biggest contribution wins', () {
      final choice = pickAppliedTargetEpisode([
        _appliedEpisode('a', count: 2, number: 1),
        _appliedEpisode('b', count: 9, number: 2),
        _appliedEpisode('c', count: 4, number: 3),
      ], requestEpisodeId: 'not-in-the-response');

      expect(choice!.target.id, 'b');
      expect(choice.others.map((e) => e.id), ['a', 'c']);
    });

    test('a schedule apply (no applied episodes) routes nowhere', () {
      expect(
        pickAppliedTargetEpisode(const [], requestEpisodeId: _episodeId),
        isNull,
      );
    });

    test('ties keep the server order (no arbitrary pick)', () {
      final choice = pickAppliedTargetEpisode([
        _appliedEpisode('first', count: 3, number: 1),
        _appliedEpisode('second', count: 3, number: 2),
      ], requestEpisodeId: null);

      expect(choice!.target.id, 'first');
    });
  });

  group('post-apply routing', () {
    late CacheDatabase db;
    late _FakeAiImportRepository repo;
    late ProviderContainer container;
    late FakeSecureStoragePlatform storage;
    late StreamController<AiApplyRunState> runStates;
    late int scenesFetches;
    late int scriptFetches;

    /// How often the block's episode LIST seam was read. The navigation path
    /// must not touch it (CodeRabbit #802): the number fallback is a cache read.
    late int episodeListFetches;

    setUp(() {
      storage = FakeSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = storage;
      runStates = StreamController<AiApplyRunState>.broadcast();
      scenesFetches = 0;
      scriptFetches = 0;
      episodeListFetches = 0;
    });

    tearDown(() async {
      await runStates.close();
    });

    Future<void> setupContainer({
      required List<Result<ApplyAiImportResponse>> applyQueue,
      bool seasonResolvable = true,
      bool seasonCached = true,
      // Seed the block's cached episode row (the number fallback's source).
      bool cachedEpisodeRow = false,
    }) async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      repo = _FakeAiImportRepository(BreakdownApi(), AiImportJobsCacheDao(db));
      repo.applyQueue.addAll(applyQueue);
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          aiImportRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
          aiPreviewProvider.overrideWith(
            (ref, jobId) async => Right(_previewResponse()),
          ),
          aiJobContextProvider.overrideWith(
            (ref, jobId) async => const AiJobContext(
              episodeId: _episodeId,
              projectId: 'series-1',
            ),
          ),
          aiJobBlockInfoProvider.overrideWith(
            (ref, jobId) async => (blockId: _blockId, projectId: 'series-1'),
          ),
          aiJobAppliedProvider.overrideWith((ref, jobId) async => false),
          aiApplyJobSeasonIdProvider.overrideWith(
            (ref, jobId) async => seasonResolvable ? _seasonId : null,
          ),
          // The apply-run stream: a silent, controllable channel — the card
          // renders its waiting line and nothing else (the run's own states are
          // covered by apply_progress_card_test.dart).
          aiApplyRunProvider(_jobId).overrideWith((ref) => runStates.stream),
          seasonRepositoryProvider.overrideWithValue(
            _ScriptedSeasonRepository(
              BreakdownApi(),
              SeasonCacheDao(db),
              seasonCached ? [season(_seasonId, title: 'S1')] : const [],
            ),
          ),
          seasonsListFetchProvider.overrideWith(
            (ref) async => Right([season(_seasonId, title: 'S1')]),
          ),
          // Counting overrides: the AC asserts the apply re-arms these seams.
          seasonScriptFetchProvider.overrideWith((ref, season) async {
            scriptFetches++;
            return const Right(SeasonScript.empty());
          }),
          scenesListFetchProvider(_episodeId).overrideWith((ref) async {
            scenesFetches++;
            return const Right(<SceneView>[]);
          }),
          // A counter, not a fake result: the routing path must never own a
          // network read (see the cache-fallback test below).
          episodesListFetchProvider(_blockId, _seasonId).overrideWith((
            ref,
          ) async {
            episodeListFetches++;
            return const Right(<EpisodeView>[]);
          }),
          membershipFetchProvider(_seasonId)
              .overrideWith((ref) async => const Left(ProblemError(code: 'x'))),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
      await AiImportJobsCacheDao(db).upsertWithEpisodeContext(
        _succeededJob(),
        DateTime.utc(2026, 1, 1),
        episodeId: _episodeId,
        projectId: 'series-1',
      );
      if (cachedEpisodeRow) {
        await EpisodeCacheDao(db).upsert(
          EpisodeView(
            (b) => b
              ..id = _episodeId
              ..blockId = _blockId
              ..projectId = 'series-1'
              ..number = 299
              ..name = 'Erlösung'
              ..updatedAt = DateTime.utc(2026, 1, 1)
              ..version = 1,
          ),
          DateTime.utc(2026, 1, 1),
        );
      }
      // Keep the scene seam WARM: an invalidation only re-runs a provider the
      // test is actually listening to, so the count would prove nothing on a
      // disposed autoDispose instance.
      container.listen(scenesListFetchProvider(_episodeId), (_, _) {});
      await container.read(scenesListFetchProvider(_episodeId).future);
    }

    /// The production topology: the Script destination is already mounted (the
    /// shell's `IndexedStack` keeps all three alive) and the import stack sits
    /// above it on the same navigator.
    /// The production topology: the Script destination lives on its OWN nested
    /// navigator (the shell's per-destination navigator, always mounted), while
    /// the import stack is pushed on the root navigator — the route tree the
    /// apply pops.
    Future<({GlobalKey<NavigatorState> root, GlobalKey<NavigatorState> script})>
    pumpWithImportStack(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final rootKey = GlobalKey<NavigatorState>();
      final scriptKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootKey,
            home: Navigator(
              key: scriptKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const ScriptTabScreen(),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      // NOT awaited: `push` completes when the route is POPPED, and this route
      // is exactly the one the apply pops.
      unawaited(
        rootKey.currentState!.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'ai-preview'),
            builder: (_) => const AiPreviewScreen(jobId: _jobId),
          ),
        ),
      );
      await pumpFrames(tester);
      return (root: rootKey, script: scriptKey);
    }

    Future<void> acknowledgeAndApply(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pump();
      final applyButton = find.byKey(const Key('ai-apply-submit'));
      await tester.ensureVisible(applyButton);
      await tester.pump();
      await tester.tap(applyButton);
      await pumpFrames(tester, n: 20);
    }

    testWidgets(
      'a successful apply leaves the preview for the Script destination with '
      'the imported episode in scope and re-arms the scene + script seams',
      (tester) async {
        await setupContainer(
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [
                  _appliedEpisode(
                    _episodeId,
                    count: 30,
                    number: 299,
                    name: 'Erlösung',
                  ),
                  _appliedEpisode(
                    _otherEpisodeId,
                    count: 5,
                    number: 298,
                    name: 'Ankunft',
                  ),
                ],
              ),
            ),
          ],
        );
        expect(scenesFetches, 1);
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        // 1. The review screen is LEFT — not "the outcome card renders in place".
        expect(find.byType(AiPreviewScreen), findsNothing);
        // 2. The shell's destination is Script and the sticky scope names the
        //    imported episode (id + number + name), with its block cascaded.
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kScriptTabIndex,
        );
        final scope = container.read(activeEpisodeProvider);
        expect(scope, isNotNull);
        expect(scope!.episodeId, _episodeId);
        expect(scope.episodeNumber, 299);
        expect(scope.episodeName, 'Erlösung');
        expect(scope.blockId, _blockId);
        expect(container.read(activeBlockProvider)!.blockId, _blockId);
        // 3. The report reached the destination: the outcome AND the additional
        //    episode of the multi-episode document.
        expect(find.byKey(const Key('ai-post-import-report')), findsOneWidget);
        expect(
          find.byKey(
            const Key('ai-post-import-other-episode-$_otherEpisodeId'),
          ),
          findsOneWidget,
        );
        final report = container.read(aiPostImportReportProvider);
        expect(report, isNotNull);
        expect(report!.episodeId, _episodeId);
        expect(report.others.map((e) => e.id), [_otherEpisodeId]);
        // 4. The scene seam was invalidated (re-run through the override) and
        //    the season-script composition was re-armed.
        expect(scenesFetches, 2);
        expect(scriptFetches, greaterThan(0));
      },
    );

    testWidgets(
      'a partially applied response keeps its unapplied outfits reachable on '
      'the destination (no silent loss after navigation)',
      (tester) async {
        await setupContainer(
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [
                  _appliedEpisode(
                    _episodeId,
                    count: 30,
                    number: 299,
                    name: 'Erlösung',
                  ),
                ],
                unappliedOutfits: [_unappliedOutfit()],
              ),
            ),
          ],
        );
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        expect(find.byType(AiPreviewScreen), findsNothing);
        expect(find.byKey(const Key('ai-post-import-report')), findsOneWidget);
        // The row that did NOT become a look is named with its reason at the
        // destination, not only in the review screen that no longer exists.
        expect(
          find.byKey(const Key('ai-post-import-unapplied-outfit-draft-1-2')),
          findsOneWidget,
        );
        // Dismissing clears it (and only it).
        await tester.tap(
          find.byKey(const Key('ai-post-import-report-dismiss')),
        );
        await pumpFrames(tester);
        expect(find.byKey(const Key('ai-post-import-report')), findsNothing);
        expect(container.read(aiPostImportReportProvider), isNull);
      },
    );

    testWidgets(
      'the destination resets its own nested navigator to the root route when '
      'a report lands (a stale detail never hides the imported rows)',
      (tester) async {
        await setupContainer(
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [
                  _appliedEpisode(
                    _episodeId,
                    count: 3,
                    number: 299,
                    name: 'Erlösung',
                  ),
                ],
              ),
            ),
          ],
        );
        final keys = await pumpWithImportStack(tester);
        // A detail pushed onto the Script destination BEFORE the apply: it
        // belongs to the pre-import scope.
        unawaited(
          keys.script.currentState!.push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'stale-detail'),
              builder: (_) => const Scaffold(body: Text('stale detail')),
            ),
          ),
        );
        await pumpFrames(tester);
        // The preview route sits above it, so the detail is in the tree but
        // offstage — the finder must look past the offstage flag to see it.
        expect(find.text('stale detail', skipOffstage: false), findsOneWidget);

        await acknowledgeAndApply(tester);

        expect(find.text('stale detail', skipOffstage: false), findsNothing);
        expect(find.byKey(const Key('ai-post-import-report')), findsOneWidget);
      },
    );

    testWidgets(
      'an unresolvable destination keeps the review screen with the outcome '
      'card and an explicit hint (honest degradation)',
      (tester) async {
        await setupContainer(
          seasonResolvable: false,
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [
                  _appliedEpisode(
                    _episodeId,
                    count: 30,
                    number: 299,
                    name: 'Erlösung',
                  ),
                ],
              ),
            ),
          ],
        );
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        // Still on the review screen, with the full outcome — and saying WHY
        // it did not move.
        expect(find.byType(AiPreviewScreen), findsOneWidget);
        expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
        expect(
          find.byKey(const Key('ai-apply-navigation-unresolved')),
          findsOneWidget,
        );
        // No half-navigation: the destination and the scopes are untouched.
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kCastTabIndex,
        );
        expect(container.read(activeEpisodeProvider), isNull);
        expect(container.read(aiPostImportReportProvider), isNull);
      },
    );

    testWidgets(
      'an uncached import season is an unresolvable destination too (no '
      'network read on the navigation path)',
      (tester) async {
        await setupContainer(
          seasonCached: false,
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [
                  _appliedEpisode(
                    _episodeId,
                    count: 30,
                    number: 299,
                    name: 'Erlösung',
                  ),
                ],
              ),
            ),
          ],
        );
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        expect(find.byType(AiPreviewScreen), findsOneWidget);
        expect(
          find.byKey(const Key('ai-apply-navigation-unresolved')),
          findsOneWidget,
        );
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kCastTabIndex,
        );
      },
    );
    testWidgets(
      'a schedule apply (no applied episodes) keeps the review screen without '
      'the episode-opening hint (CodeRabbit #802)',
      (tester) async {
        await setupContainer(
          applyQueue: [
            // A schedule apply merges onto the project's existing scenes and
            // days, so it names no target episode at all.
            Right(_outcome(appliedEpisodes: const [])),
          ],
        );
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        expect(find.byType(AiPreviewScreen), findsOneWidget);
        expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
        // No claim about an episode that does not exist — and no navigation.
        expect(
          find.byKey(const Key('ai-apply-navigation-unresolved')),
          findsNothing,
        );
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kCastTabIndex,
        );
        expect(container.read(aiPostImportReportProvider), isNull);
      },
    );

    testWidgets(
      'a missing episode number is read from the block cache, never from the '
      'network (CodeRabbit #802)',
      (tester) async {
        await setupContainer(
          // The response carries no number for the target; the block's cached
          // episode row does.
          cachedEpisodeRow: true,
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [_appliedEpisode(_episodeId, count: 30)],
              ),
            ),
          ],
        );
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        // Routed with the CACHED number/name...
        final scope = container.read(activeEpisodeProvider);
        expect(scope, isNotNull);
        expect(scope!.episodeId, _episodeId);
        expect(scope.episodeNumber, 299);
        expect(scope.episodeName, 'Erlösung');
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kScriptTabIndex,
        );
        // ...and the episode LIST seam was never read: the navigation path owns
        // no network request.
        expect(episodeListFetches, 0);
      },
    );

    testWidgets(
      'the report card bounds its detail area so a long report cannot starve '
      'the script list (CodeRabbit #802)',
      (tester) async {
        await setupContainer(
          applyQueue: [
            Right(
              _outcome(
                appliedEpisodes: [
                  _appliedEpisode(
                    _episodeId,
                    count: 30,
                    number: 299,
                    name: 'Erlösung',
                  ),
                ],
                unappliedOutfits: [
                  for (var i = 0; i < 12; i++) _unappliedOutfit(ordinal: i),
                ],
              ),
            ),
          ],
        );
        await pumpWithImportStack(tester);

        await acknowledgeAndApply(tester);

        // The detail rows live in a BOUNDED scroll view: without the
        // `ConstrainedBox` the card would take its content height and push the
        // script body out of the viewport.
        final details = find.byKey(const Key('ai-post-import-report-details'));
        expect(details, findsOneWidget);
        expect(tester.getSize(details).height, lessThan(500));
        // The script body still gets real space.
        expect(
          tester.getSize(find.byType(ScriptTabScreen)).height,
          greaterThan(0),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('shared outcome copy (issue #759)', () {
    test('a script apply with figure/piece counts uses the script wording', () {
      final l10n = AppLocalizationsEn();
      final line = aiApplyOutcomeLine(
        l10n,
        ApplyAiImportResponse(
          (b) => b
            ..appliedCount = 57
            ..createdDays = 0
            ..plannedSceneShoots = 0
            ..createdCharacters = 4
            ..createdPieces = 12
            ..createdOutfits = 6
            ..createdEpisodes = 1
            ..unappliedOutfits.replace(const <UnappliedOutfit>[]),
        ),
      );

      expect(line, contains('57'));
      expect(line, contains('4'));
      expect(line, contains('6'));
      expect(line, contains('12'));
    });
  });
}
