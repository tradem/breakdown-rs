// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.4 (opencode-go)

// Tier-1 + Tier-2 tests for the Pass-2 outfit provenance badges and the
// wardrobe-gap candidate picker (issue #745, OpenSpec
// `ai-import-decision-outfit-continuity`): the four origins rendered on the
// preview rows, the suppressed (empty) source quote of a Pass-2 look, the
// one-tap gap resolution and its wire form (`continuity_selections`), the
// re-apply narrative of a stale pick, and the goldens.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

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
  defaultProjectId: 'project-1',
);

AiConfigView _namingConfig() => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = 'assistant-model-1'
    ..provider = LlmProvider.openai
    ..vaultKeyId = 'vk-1'
    ..prompts.replace(BuiltMap<String, String>())
    ..promptKinds.replace(BuiltList<DocumentKind>())
    ..revoked = false
    ..version = 1,
);

DraftOutfit _outfit(
  String character,
  String name, {
  String quote = '',
  DraftOutfitOrigin? origin,
  DraftOutfitProvenance? provenance,
}) => DraftOutfit((b) {
  b
    ..characterName = character
    ..name = name
    ..sourceQuote = quote
    ..origin = origin;
  // An absent provenance stays UNSET on the wire (every Pass-1 row).
  if (provenance != null) b.provenance.replace(provenance);
});

DraftScene _scene(
  String ref, {
  int? number,
  List<String> characters = const [],
  List<DraftOutfit> outfits = const [],
}) => DraftScene(
  (b) => b
    ..draftRef = ref
    ..sceneNumber = number
    ..summary = 'Handlung $ref'
    ..characters.replace([
      for (final name in characters)
        DraftCharacter(
          (c) => c
            ..name = name
            ..category = CharacterCategory.mainCast,
        ),
    ])
    ..outfits.replace(outfits),
);

DraftOutfitCandidate _candidate(
  DraftOutfitOrigin origin,
  String name, {
  required String sourceDraftRef,
  int? sourceSceneNumber,
  double confidence = 0.6,
}) => DraftOutfitCandidate(
  (b) => b
    ..origin = origin
    ..name = name
    ..sourceDraftRef = sourceDraftRef
    ..confidence = confidence
    ..sourceSceneNumber = sourceSceneNumber,
);

Uncertainty _gap(
  int sceneIndex, {
  required String note,
  List<DraftOutfitCandidate> candidates = const [],
}) => Uncertainty(
  (b) => b
    ..sceneIndex = sceneIndex
    ..field = 'outfits'
    ..kind = UncertaintyKind.droppedRow
    ..note = note
    ..candidates.replace(candidates),
);

AiPreviewPayload _scriptPayload(
  List<DraftScene> scenes, {
  List<Uncertainty> uncertainties = const [],
}) => AiPreviewPayload(
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
                    ..scenes.replace(scenes)
                    ..uncertainties.replace(uncertainties),
                ),
              ),
          ),
        ),
);

AiImportPreviewResponse _previewResponse(AiPreviewPayload payload) =>
    AiImportPreviewResponse(
      (b) => b
        ..jobId = 'job-1'
        ..documentKind = DocumentKind.schedule
        ..status = JobStatus.succeeded
        ..preview.replace(payload),
    );

AiImportJob _succeededJob(String id) => AiImportJob(
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
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

ApplyAiImportResponse _outcome() => ApplyAiImportResponse(
  (b) => b
    ..appliedCount = 2
    ..createdDays = 0
    ..plannedSceneShoots = 0
    ..createdCharacters = 0
    ..createdPieces = 0
    ..createdOutfits = 1
    ..createdEpisodes = 0,
);

/// Repository fake: records every apply request, replays scripted outcomes.
class FakeAiImportRepository extends AiImportRepository {
  FakeAiImportRepository(super.api, super.cache);

  final List<Result<ApplyAiImportResponse>> applyQueue = [];
  ApplyAiImportRequest? lastRequest;

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async {
    lastRequest = request;
    return applyQueue.removeAt(0);
  }
}

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

// --- Scenarios --------------------------------------------------------------

/// A two-row script: scene 4 dresses BEN and ANNA, scene 5 names both without
/// an outfit — the canonical Pass-2 gap of the OpenSpec change.
AiPreviewPayload _gapPayload({bool withCandidates = true}) => _scriptPayload(
  [
    _scene(
      'row-4',
      number: 4,
      outfits: [
        _outfit(
          'BEN',
          'Zivil-Look',
          quote: 'trägt Zivil',
          origin: DraftOutfitOrigin.explicitQuote,
        ),
      ],
    ),
    _scene('row-5', number: 5, characters: ['BEN', 'ANNA']),
  ],
  uncertainties: [
    _gap(
      1,
      note:
          'no certain wardrobe state for BEN (confidence 0.60); '
          'pick a look or leave the scene empty',
      candidates: withCandidates
          ? [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-4',
                sourceSceneNumber: 4,
              ),
              _candidate(
                DraftOutfitOrigin.inferredFromContext,
                'Kontext-Look (OP-SAAL)',
                sourceDraftRef: 'row-5',
                sourceSceneNumber: 5,
              ),
            ]
          : const [],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Provenance badges (issue #745)', () {
    test('every origin maps to its own localized label', () {
      // The labels are ARB-catalog copy, never the wire slug (a reviewer must
      // not read `continued_from_scene`).
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(l10n.aiPreviewOutfitOriginExplicit, 'quoted from the script');
      expect(l10n.aiPreviewOutfitOriginDerived, 'derived from the script');
      expect(
        l10n.aiPreviewOutfitOriginContinued('4'),
        'continued from scene 4',
      );
      expect(
        l10n.aiPreviewOutfitOriginContinuedNoScene,
        'continued from an earlier scene',
      );
      expect(
        l10n.aiPreviewOutfitOriginInferred,
        'inferred from the scene context',
      );
    });
  });

  group('Preview + apply widget tests', () {
    late CacheDatabase db;
    late FakeAiImportRepository repo;
    late ProviderContainer container;

    Future<void> setupContainer({
      required AiPreviewPayload payload,
      List<Result<ApplyAiImportResponse>>? applyQueue,
    }) async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = AiImportJobsCacheDao(db);
      repo = FakeAiImportRepository(BreakdownApi(), dao);
      if (applyQueue != null) repo.applyQueue.addAll(applyQueue);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
          aiPreviewProvider.overrideWith(
            (ref, jobId) async => Right(_previewResponse(payload)),
          ),
          aiJobContextProvider.overrideWith(
            (ref, jobId) async =>
                const AiJobContext(episodeId: 'ep-1', projectId: 'project-1'),
          ),
          scenesListFetchProvider.overrideWith(
            (ref, episodeId) async => const Right(<SceneView>[]),
          ),
          // The preview + apply screens render the configured naming line
          // (issue #608): a deterministic override keeps the tests off the
          // real discovery path and the goldens stable.
          configuredAiNamingProvider.overrideWith(
            (ref) => Future.value(_namingConfig()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
      await dao.upsertWithEpisodeContext(
        _succeededJob('job-1'),
        DateTime.utc(2026, 1, 1),
        episodeId: 'ep-1',
        projectId: 'project-1',
      );
    }

    Future<void> pumpPreview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiPreviewScreen(jobId: 'job-1')),
        ),
      );
      // Seed is fire-and-forget; pump until the rows land.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('all four origins render a badge, a Pass-2 look renders no '
        'quote (it has none)', (tester) async {
      await setupContainer(
        payload: _scriptPayload([
          _scene(
            'row-1',
            number: 1,
            outfits: [
              _outfit(
                'BEN',
                'Zivil-Look',
                quote: 'trägt Zivil',
                origin: DraftOutfitOrigin.explicitQuote,
              ),
              _outfit(
                'BEN',
                'Abgeleiteter Look',
                quote: 'aus dem Auftritt',
                origin: DraftOutfitOrigin.derived,
              ),
              _outfit(
                'ANNA',
                'Zivil-Look',
                origin: DraftOutfitOrigin.continuedFromScene,
                provenance: DraftOutfitProvenance(
                  (p) => p
                    ..sourceDraftRef = 'row-0'
                    ..sourceSceneNumber = 4
                    ..confidence = 0.91,
                ),
              ),
              _outfit(
                'CARLA',
                'Kontext-Look (OP-SAAL)',
                origin: DraftOutfitOrigin.inferredFromContext,
                provenance: DraftOutfitProvenance((p) => p..confidence = 0.84),
              ),
            ],
          ),
        ]),
      );
      await pumpPreview(tester);

      expect(
        find.byKey(const Key('ai-preview-outfit-origin-row-1-0')),
        findsOneWidget,
      );
      expect(find.text('quoted from the script'), findsOneWidget);
      expect(find.text('derived from the script'), findsOneWidget);
      // A continuation names the source scene the provenance carries.
      expect(find.text('continued from scene 4'), findsOneWidget);
      expect(find.text('inferred from the scene context'), findsOneWidget);

      // Pass-1 rows keep their grounding evidence …
      expect(find.text('Source: trägt Zivil'), findsOneWidget);
      expect(find.text('Source: aus dem Auftritt'), findsOneWidget);
      // … a Pass-2 row has none, and must not pretend it was quoted.
      expect(find.textContaining('Source: '), findsNWidgets(2));
    });

    testWidgets('a stored preview without an origin renders NO badge', (
      tester,
    ) async {
      await setupContainer(
        payload: _scriptPayload([
          _scene(
            'row-1',
            number: 1,
            outfits: [_outfit('BEN', 'Zivil-Look', quote: 'trägt Zivil')],
          ),
        ]),
      );
      await pumpPreview(tester);

      expect(
        find.byKey(const Key('ai-preview-outfit-origin-row-1-0')),
        findsNothing,
      );
      expect(find.text('Source: trägt Zivil'), findsOneWidget);
    });

    testWidgets('a gap renders one chip per script-derivable candidate plus '
        'the leave-empty option, empty by default', (tester) async {
      await setupContainer(payload: _gapPayload());
      await pumpPreview(tester);

      const keyBase = '1-ben';
      expect(find.byKey(const Key('ai-preview-gap-$keyBase')), findsOneWidget);
      // A candidate-carrying gap renders the picker, never the plain notice
      // (issue #748: the notice's per-uncertainty key must be absent here).
      expect(find.byKey(const Key('ai-preview-notice-0')), findsNothing);
      expect(find.text('Wardrobe gap · scene 5 · BEN'), findsOneWidget);
      expect(
        find.byKey(const Key('ai-preview-gap-pick-$keyBase-continued')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-preview-gap-pick-$keyBase-inferred')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-preview-gap-pick-$keyBase-empty')),
        findsOneWidget,
      );
      // The candidates carry the look names AND the server's confidence.
      expect(
        find.text('Continuation: Zivil-Look · 60% confidence'),
        findsOneWidget,
      );
      expect(
        find.text('Context look: Kontext-Look (OP-SAAL) · 60% confidence'),
        findsOneWidget,
      );
      // Nothing is picked before the reviewer decides.
      final empty = tester.widget<ChoiceChip>(
        find.byKey(const Key('ai-preview-gap-pick-$keyBase-empty')),
      );
      expect(empty.selected, isTrue);
      // The dispatch-point summary states the deliberate emptiness.
      expect(
        find.text('Scene 5 · BEN → no look (deliberately empty)'),
        findsOneWidget,
      );
    });

    testWidgets('a gap without candidates keeps the plain notice — no '
        'invented option', (tester) async {
      await setupContainer(payload: _gapPayload(withCandidates: false));
      await pumpPreview(tester);

      expect(find.byKey(const Key('ai-preview-gap-1-ben')), findsNothing);
      expect(find.textContaining('Uncertainty (outfits)'), findsOneWidget);
      // The plain notice carries a stable per-uncertainty key (issue #748):
      // the on-device Gherkin scenario asserts the candidate-less gap by key
      // instead of matching localized prose, so the key must exist here too.
      expect(find.byKey(const Key('ai-preview-notice-0')), findsOneWidget);
      // The picker replaces the plain notice: the two never render together
      // for the same uncertainty.
      expect(find.byKey(const Key('ai-preview-gap-1-ben')), findsNothing);
    });

    testWidgets('two gaps in ONE scene render two distinct cards, even with '
        'identical note text', (tester) async {
      // CodeRabbit review: matching a gap to its uncertainty by scene + note
      // rendered the same card twice (identical widget key → debug assertion)
      // for notes the server may legitimately repeat. The pairing is by the
      // uncertainty's own index now.
      const repeated = 'no certain wardrobe state; pick a look or leave empty';
      await setupContainer(
        payload: _scriptPayload(
          [
            _scene(
              'row-4',
              number: 4,
              outfits: [
                _outfit('BEN', 'Zivil-Look'),
                _outfit('ANNA', 'Dienst-Look'),
              ],
            ),
            _scene('row-5', number: 5, characters: ['BEN', 'ANNA']),
          ],
          uncertainties: [
            _gap(
              1,
              note: repeated,
              candidates: [
                _candidate(
                  DraftOutfitOrigin.continuedFromScene,
                  'Zivil-Look',
                  sourceDraftRef: 'row-4',
                ),
              ],
            ),
            _gap(
              1,
              note: repeated,
              candidates: [
                _candidate(
                  DraftOutfitOrigin.continuedFromScene,
                  'Dienst-Look',
                  sourceDraftRef: 'row-4',
                ),
              ],
            ),
          ],
        ),
      );
      await pumpPreview(tester);

      expect(find.byKey(const Key('ai-preview-gap-1-ben')), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-gap-1-anna')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking the continuation sends continuity_selections and '
        'counts as a review edit', (tester) async {
      await setupContainer(
        payload: _gapPayload(),
        applyQueue: [Right(_outcome())],
      );
      await pumpPreview(tester);

      await tester.tap(
        find.byKey(const Key('ai-preview-gap-pick-1-ben-continued')),
      );
      await tester.pumpAndSettle();

      final pick = tester.widget<ChoiceChip>(
        find.byKey(const Key('ai-preview-gap-pick-1-ben-continued')),
      );
      expect(pick.selected, isTrue);
      expect(
        find.text('Scene 5 · BEN → Zivil-Look'),
        findsOneWidget,
        reason: 'the dispatch point names the look the pick applies',
      );

      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      final request = repo.lastRequest!;
      final selections = request.continuitySelections!;
      expect(selections, hasLength(1));
      expect(selections.single.sceneIndex, 1);
      // The identity key the SERVER validates — derived from the scene's own
      // character list, case-folded.
      expect(selections.single.characterIdentity, 'ben');
      expect(selections.single.candidate, OutfitContinuityCandidate.continued);
      // A pick changes what the apply creates: it is a review edit.
      expect(request.acceptAsIs, isFalse);
      expect(request.editDistance, 1);
    });

    testWidgets('leaving the gap unresolved applies WITHOUT a selection', (
      tester,
    ) async {
      await setupContainer(
        payload: _gapPayload(),
        applyQueue: [Right(_outcome())],
      );
      await pumpPreview(tester);

      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      final request = repo.lastRequest!;
      // Absent on the wire: the backend then applies the scene without an
      // outfit (never with an invented one).
      expect(request.continuitySelections, isNull);
      expect(request.acceptAsIs, isTrue);
    });

    testWidgets('a stale pick answers 409 apply-unknown-continuity-candidate '
        'with the refresh narrative', (tester) async {
      await setupContainer(
        payload: _gapPayload(),
        applyQueue: [
          Left(
            const ProblemError(
              code: 'ai-import.apply-unknown-continuity-candidate',
              status: 409,
            ),
          ),
        ],
      );
      await pumpPreview(tester);

      await tester.tap(
        find.byKey(const Key('ai-preview-gap-pick-1-ben-continued')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      final error = tester.widget<Text>(
        find.byKey(const Key('ai-apply-error')),
      );
      expect(
        error.data,
        'The preview no longer offers this wardrobe choice — '
        'refresh the preview and apply again.',
      );
    });

    testWidgets('a successful RETRY clears the earlier command error instead '
        'of rendering both', (tester) async {
      // CodeRabbit review: `copyWith` keeps `commandError` when the argument is
      // omitted, so the pre-change re-construction's implicit reset had to be
      // restored explicitly — otherwise the error card outlives its cause and
      // sits next to the freshly rendered outcome.
      await setupContainer(
        payload: _gapPayload(),
        applyQueue: [
          Left(
            const ProblemError(
              code: 'ai-import.apply-unknown-continuity-candidate',
              status: 409,
            ),
          ),
          Right(_outcome()),
        ],
      );
      await pumpPreview(tester);

      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-apply-error')), findsOneWidget);

      // Retry: the preview now accepts the request.
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-apply-error')), findsNothing);
      expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
    });

    group('goldens: provenance badges + gap picker', () {
      Future<void> pumpGolden(
        WidgetTester tester, {
        required String golden,
        required ThemeMode mode,
        required TargetPlatform platform,
      }) async {
        try {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData.light(),
                darkTheme: ThemeData.dark(),
                themeMode: mode,
                // AGENTS.md §9: goldens use the GERMAN template locale, so the
                // template copy (not the English fallback) is what the picture
                // pins.
                locale: const Locale('de'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const AiPreviewScreen(jobId: 'job-1'),
              ),
            ),
          );
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          await expectLater(
            find.byType(AiPreviewScreen),
            matchesGoldenFile('goldens/$golden'),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }

      for (final (mode, modeName) in [
        (ThemeMode.light, 'light'),
        (ThemeMode.dark, 'dark'),
      ]) {
        for (final (platform, platformName) in [
          (TargetPlatform.android, 'android'),
          (TargetPlatform.macOS, 'macos'),
        ]) {
          testWidgets('continuity golden $modeName $platformName', (
            tester,
          ) async {
            await setupContainer(payload: _gapPayload());
            await pumpGolden(
              tester,
              golden: 'ai_preview_continuity_${modeName}_$platformName.png',
              mode: mode,
              platform: platform,
            );
          });
        }
      }
    });
  });
}
