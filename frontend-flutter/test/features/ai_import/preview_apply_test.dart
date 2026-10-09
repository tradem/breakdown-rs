// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-1 + Tier-2 tests for the preview + apply features
// (`flutter-ai-import-workflow` tasks 4.3/4.4): the typed-preview
// rendering (script/schedule/merged + unknown-`kind` degraded + empty),
// the mapping-request builder (Create / Update-from-picked-DTO / skip;
// verbatim `draft_ref`s), the apply round-trip against a fake (incl. the
// ambiguous-timeout reconciliation), the episode context for fresh-job
// AND remembered-job entry (incl. the missing-context → picker-required
// path), 409/403 branches, and goldens.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
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
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';

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
  defaultProjectId: 'series-1',
);

/// The configured naming fixture the naming line renders (issue #608).
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

DraftScene _draft(
  String ref, {
  int? number,
  List<DraftCostume> costumes = const [],
  DraftEpisode? episode,
}) => DraftScene((b) {
  b
    ..draftRef = ref
    ..sceneNumber = number
    ..summary = 'Scene $ref'
    ..characters.replace(const <String>['ch-1'])
    ..costumes.replace(costumes);
  // A complex built_value field is set through its builder; an absent
  // marker stays UNSET (null on the wire — the single-episode flow).
  if (episode != null) b.episode.replace(episode);
});

/// The `Ep.:` marker metadata a draft row carries (issue #581).
DraftEpisode _episodeMeta(int? number, String? title) => DraftEpisode(
  (b) => b
    ..number = number
    ..title = title,
);

EpisodeView _cachedEpisode(String id, {int number = 2}) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = 'block-1'
    ..number = number
    ..projectId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

DraftCostume _costume(String character, String description, {String? quote}) =>
    DraftCostume(
      (b) => b
        ..characterName = character
        ..description = description
        ..sourceQuote = quote ?? 'trägt $description',
    );

SceneView _scene(String id, {int version = 1, int? number}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = false
    ..sceneNumber = number
    ..shootingDayIds.replace(const <String>[])
    ..summary = 'Existing $id'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

ShootingScheduleRow _scheduleRow(String ref) => ShootingScheduleRow(
  (b) => b
    ..rowRef = ref
    ..sceneNumber = 12
    ..order = 1,
);

/// Wraps script draft rows into the typed preview payload's `OneOf` variant 3.
/// (The oneOf nesting is deep enough that inlining it per test hurts readability.)
AiPreviewPayload _scriptPayloadWith(
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
                    ..title = 'Pilot'
                    ..scenes.replace([_draft('draft-1'), _draft('draft-2')])
                    ..uncertainties.replace([
                      Uncertainty(
                        (u) => u
                          ..field = 'location'
                          ..note = 'Unknown stage'
                          ..sceneIndex = 1,
                      ),
                    ]),
                ),
              ),
          ),
        ),
);

AiPreviewPayload _mergedPayload() => AiPreviewPayload(
  (b) => b
    ..oneOf =
        OneOf.fromValue3<
          AiPreviewPayloadOneOf,
          AiPreviewPayloadOneOf1,
          AiPreviewPayloadOneOf2
        >(
          value: AiPreviewPayloadOneOf2(
            (b) => b
              ..kind = AiPreviewPayloadOneOf2KindEnum.merged
              ..data.replace(
                MergedPreview(
                  (b) => b
                    ..scenes.replace([
                      MergedScene(
                        (m) => m
                          ..scene.replace(_scene('sc-1', number: 12))
                          ..scheduleRows.replace([_scheduleRow('row-1')]),
                      ),
                    ])
                    ..unmatchedScheduleRows.replace([_scheduleRow('row-x')])
                    ..unmatchedScriptScenes.replace(
                      BuiltList(const <SceneView>[]),
                    ),
                ),
              ),
          ),
        ),
);

AiPreviewPayload _preMergePayload() => AiPreviewPayload(
  (b) => b
    ..oneOf =
        OneOf.fromValue3<
          AiPreviewPayloadOneOf,
          AiPreviewPayloadOneOf1,
          AiPreviewPayloadOneOf2
        >(
          value: AiPreviewPayloadOneOf1(
            (b) => b
              ..kind = AiPreviewPayloadOneOf1KindEnum.schedule
              ..data.replace(
                ShootingSchedule(
                  (b) => b..rows.replace([_scheduleRow('row-1')]),
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

/// Repository fake with scripted, QUEUED apply outcomes (the
/// reconciliation round-trip driver).
class FakeAiImportRepository extends AiImportRepository {
  FakeAiImportRepository(super.api, super.cache);

  final List<Result<ApplyAiImportResponse>> applyQueue = [];
  final List<ApplyAiImportRequest> applyRequests = [];
  Result<AiImportJob>? jobResult;

  ApplyAiImportRequest? lastRequest;

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async {
    applyRequests.add(request);
    lastRequest = request;
    return applyQueue.removeAt(0);
  }

  @override
  Future<Result<AiImportJob>> getJobAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async {
    final job = jobResult;
    if (job != null) {
      final view = job.getRight().toNullable();
      if (view != null) {
        await cache.upsertAll([view], clock.now());
        return Right(view);
      }
    }
    return Left(const ProblemError(code: 'ai-import.not-found'));
  }
}

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

ApplyAiImportResponse _outcome({
  int appliedCount = 2,
  int createdDays = 1,
  int plannedSceneShoots = 3,
  int createdCharacters = 0,
  int createdCostumes = 0,
  // issue #581 backend: episodes a NEW draft-episode group created. The
  // single-episode fixtures of this suite exercise no group targets, so the
  // fixture pins the empty case explicitly.
  int createdEpisodes = 0,
  List<UnappliedCostume> unappliedCostumes = const [],
}) => ApplyAiImportResponse(
  (b) => b
    ..appliedCount = appliedCount
    ..createdDays = createdDays
    ..plannedSceneShoots = plannedSceneShoots
    ..createdCharacters = createdCharacters
    ..createdCostumes = createdCostumes
    ..createdEpisodes = createdEpisodes
    ..unappliedCostumes.addAll(unappliedCostumes),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiApplyState — mapping-request builder (task 4.3)', () {
    test('all-Create is accept_as_is with edit_distance 0', () {
      final state = AiApplyState(
        rows: const [
          PreviewRow(draftRef: 'd1', label: 'A'),
          PreviewRow(draftRef: 'd2', label: 'B'),
        ],
      );
      expect(state.acceptAsIs, isTrue);
      expect(state.editDistance, 0);
      final mappings = state.buildMappings();
      expect(mappings, hasLength(2));
      // The draft_ref is VERBATIM.
      expect(mappings.map((m) => m.draftRef), ['d1', 'd2']);
      // Create serializes as the bare "Create" string.
      // Create serializes as the bare "Create" string variant.
      expect(mappings.first.decision.oneOf.value, 'Create');
      expect(mappings.first.draftRef, 'd1');
    });

    // Tasks 2.x/7.4 (`ai-import` — costumes are decided independently of the
    // scene row): only REJECTIONS travel. An absent ordinal reads as accepted
    // server-side, so an untouched row's request stays byte-identical to a
    // pre-costume client's.
    test('an accepted costume sends NO decision; a rejected one sends its '
        'ordinal with accepted=false', () {
      final state = AiApplyState(
        rows: [
          const PreviewRow(
            draftRef: 'd1',
            label: 'A',
            costumes: [
              PreviewCostume(
                ordinal: 0,
                characterName: 'Renee',
                description: 'Blue linen dress',
                sourceQuote: 'trägt das blaue Leinenkleid',
              ),
              PreviewCostume(
                ordinal: 1,
                characterName: 'Renee',
                description: 'Leather coat',
                sourceQuote: 'greift zum Ledermantel',
              ),
            ],
          ),
        ],
      );
      expect(
        state.buildMappings().single.costumeDecisions,
        isNull,
        reason: 'default-accepted rows are not noise on the wire',
      );

      final vetoed = AiApplyState(
        rows: [state.rows.single.withCostumeDecision(1, false)],
      );
      final rejected = vetoed.buildMappings();
      final decisions = rejected.single.costumeDecisions!;
      expect(decisions, hasLength(1));
      expect(decisions.single.ordinal, 1);
      expect(decisions.single.accepted, isFalse);
    });

    test('a rejected costume is an EDIT: accept_as_is must not be claimed '
        'over a row whose extraction the reviewer vetoed', () {
      const rows = [
        PreviewRow(
          draftRef: 'd1',
          label: 'A',
          costumes: [
            PreviewCostume(
              ordinal: 0,
              characterName: 'Renee',
              description: 'Blue linen dress',
              sourceQuote: 'q',
            ),
          ],
        ),
      ];
      expect(AiApplyState(rows: rows).acceptAsIs, isTrue);
      expect(AiApplyState(rows: rows).editDistance, 0);

      final vetoed = AiApplyState(
        rows: [rows.single.withCostumeDecision(0, false)],
      );
      expect(vetoed.editDistance, 1);
      expect(vetoed.acceptAsIs, isFalse);
    });

    test('an unknown costume ordinal is ignored, never fabricating a row the '
        'payload does not carry', () {
      const row = PreviewRow(
        draftRef: 'd1',
        label: 'A',
        costumes: [
          PreviewCostume(
            ordinal: 0,
            characterName: 'Renee',
            description: 'Blue linen dress',
            sourceQuote: 'q',
          ),
        ],
      );
      expect(
        row.withCostumeDecision(7, false).costumes.single.accepted,
        isTrue,
      );
    });

    test('Update carries the picked aggregate id + version; skip is '
        'EXCLUDED from the mappings', () {
      final state = AiApplyState(
        rows: [
          const PreviewRow(draftRef: 'd1', label: 'A'),
          const PreviewRow(
            draftRef: 'd2',
            label: 'B',
          ).withDecision(const UpdateDecision(aggregateId: 'sc-9', version: 4)),
          const PreviewRow(
            draftRef: 'd3',
            label: 'C',
          ).withDecision(const SkipDecision()),
        ],
      );
      expect(state.acceptAsIs, isFalse);
      expect(state.editDistance, 2, reason: 'update + skip are user edits');
      final mappings = state.buildMappings();
      expect(mappings, hasLength(2), reason: 'the skipped row is excluded');
      // The Update variant carries the externally-tagged decision with
      // the picked aggregate id + version.
      final updateVariant =
          mappings.last.decision.oneOf.value as ApplyMappingDecisionOneOf;
      expect(updateVariant.decisionUpdate.aggregateId, 'sc-9');
      expect(updateVariant.decisionUpdate.version, 4);
    });
  });

  group('AiApplyState — draft-episode groups (issue #581)', () {
    test(
      'group ref derivation mirrors the backend group_key byte-for-byte',
      () {
        // The backend derives `ep:<n>` / `ep-t:<trimmed title>`; a ref the
        // backend does not derive would 422 the whole apply.
        expect(draftEpisodeGroupRef(_episodeMeta(3, 'Titel')), 'ep:3');
        expect(
          draftEpisodeGroupRef(_episodeMeta(null, '  Sommer ')),
          'ep-t:Sommer',
        );
        expect(draftEpisodeGroupRef(_episodeMeta(null, '   ')), isNull);
        expect(draftEpisodeGroupRef(_episodeMeta(null, null)), isNull);
        // The number wins over the title.
        expect(draftEpisodeGroupRef(_episodeMeta(7, 'Titel')), 'ep:7');
      },
    );

    test('groupRefs are first-appearance ordered and deduplicated; rows '
        'without metadata never produce a ref', () {
      final state = AiApplyState(
        rows: [
          const PreviewRow(draftRef: 'd1', label: 'A'),
          PreviewRow(
            draftRef: 'd2',
            label: 'B',
            episode: _episodeMeta(3, 'Titel'),
          ),
          PreviewRow(
            draftRef: 'd3',
            label: 'C',
            episode: _episodeMeta(3, 'Anders'),
          ),
          PreviewRow(
            draftRef: 'd4',
            label: 'D',
            episode: _episodeMeta(5, null),
          ),
          const PreviewRow(draftRef: 'd5', label: 'E'),
        ],
      );
      expect(state.groupRefs, ['ep:3', 'ep:5']);
      expect(state.episodeOfGroup('ep:3')!.title, 'Titel');
      expect(state.episodeOfGroup('ep:missing'), isNull);
    });

    test('targetFor defaults to create-new pre-filled from the heading; an '
        'explicit pick wins', () {
      final state = AiApplyState(
        rows: [
          PreviewRow(
            draftRef: 'd1',
            label: 'A',
            episode: _episodeMeta(3, 'Titel'),
          ),
        ],
      );
      final defaultTarget = state.targetFor('ep:3');
      expect(defaultTarget, isA<CreateEpisodeGroupTarget>());
      final create = defaultTarget as CreateEpisodeGroupTarget;
      expect(create.number, 3);
      expect(create.name, 'Titel');

      final picked = AiApplyState(
        rows: state.rows,
        groupTargets: const {
          'ep:3': ExistingEpisodeGroupTarget(episodeId: 'ep-9'),
        },
      );
      expect(picked.targetFor('ep:3'), isA<ExistingEpisodeGroupTarget>());
    });

    test('a group-target deviation is an edit: accept_as_is stays honest', () {
      final rows = [
        PreviewRow(
          draftRef: 'd1',
          label: 'A',
          episode: _episodeMeta(3, 'Titel'),
        ),
      ];
      expect(AiApplyState(rows: rows).editDistance, 0);
      expect(AiApplyState(rows: rows).acceptAsIs, isTrue);

      // Switching to an existing episode is an edit.
      final switched = AiApplyState(
        rows: rows,
        groupTargets: const {
          'ep:3': ExistingEpisodeGroupTarget(episodeId: 'ep-9'),
        },
      );
      expect(switched.editDistance, 1);
      expect(switched.acceptAsIs, isFalse);

      // Editing the pre-filled number is an edit, too.
      final renumbered = AiApplyState(
        rows: rows,
        groupTargets: const {
          'ep:3': CreateEpisodeGroupTarget(number: 4, name: 'Titel'),
        },
      );
      expect(renumbered.editDistance, 1);

      // Re-entering the EXACT heading values is not an edit.
      final same = AiApplyState(
        rows: rows,
        groupTargets: const {
          'ep:3': CreateEpisodeGroupTarget(number: 3, name: 'Titel'),
        },
      );
      expect(same.editDistance, 0);
    });

    test('apply gates: a create target without its wire-required number and '
        'two groups on one number keep the dispatch disabled', () {
      final titleOnly = PreviewRow(
        draftRef: 'd1',
        label: 'A',
        episode: _episodeMeta(null, 'Sommer'),
      );
      final incomplete = AiApplyState(
        rows: [titleOnly],
        context: const AiJobContext(episodeId: 'ep-1', projectId: 'series-1'),
      );
      expect(incomplete.hasCompleteGroupTargets, isFalse);

      final numbered = AiApplyState(
        rows: [titleOnly],
        context: const AiJobContext(episodeId: 'ep-1', projectId: 'series-1'),
        groupTargets: const {
          'ep-t:Sommer': CreateEpisodeGroupTarget(number: 7, name: 'Sommer'),
        },
      );
      expect(numbered.hasCompleteGroupTargets, isTrue);

      // Two groups creating the same number mirror the backend 422
      // client-side — caught before the wire.
      final twoGroups = [
        PreviewRow(
          draftRef: 'd1',
          label: 'A',
          episode: _episodeMeta(3, 'Titel'),
        ),
        PreviewRow(
          draftRef: 'd2',
          label: 'B',
          episode: _episodeMeta(null, 'Sommer'),
        ),
      ];
      final colliding = AiApplyState(
        rows: twoGroups,
        context: const AiJobContext(episodeId: 'ep-1', projectId: 'series-1'),
        groupTargets: const {
          'ep-t:Sommer': CreateEpisodeGroupTarget(number: 3, name: 'Sommer'),
        },
      );
      expect(colliding.hasDuplicateCreateNumbers, isTrue);
    });

    test('buildEpisodeGroups: existing sends kind existing + episode_id; '
        'create sends kind create + number; no metadata → empty '
        '(single-episode flow)', () {
      final grouped = AiApplyState(
        rows: [
          PreviewRow(
            draftRef: 'd1',
            label: 'A',
            episode: _episodeMeta(3, 'Titel'),
          ),
          const PreviewRow(draftRef: 'd2', label: 'B'),
        ],
        groupTargets: const {
          'ep:3': ExistingEpisodeGroupTarget(episodeId: 'ep-9'),
        },
      );
      final groups = grouped.buildEpisodeGroups();
      expect(groups, hasLength(1));
      expect(groups.single.episodeRef, 'ep:3');
      final existing = groups.single.target.oneOf.value as EpisodeTargetOneOf;
      expect(existing.episodeId, 'ep-9');
      expect(existing.kind, EpisodeTargetOneOfKindEnum.existing);

      // A title-only group with a reviewer-entered number.
      final created = AiApplyState(
        rows: [
          PreviewRow(
            draftRef: 'd1',
            label: 'A',
            episode: _episodeMeta(null, 'Sommer'),
          ),
        ],
        groupTargets: const {
          'ep-t:Sommer': CreateEpisodeGroupTarget(number: 7, name: 'Sommer'),
        },
      );
      final createGroups = created.buildEpisodeGroups();
      final create =
          createGroups.single.target.oneOf.value as EpisodeTargetOneOf1;
      expect(create.number, 7);
      expect(create.name, 'Sommer');
      expect(create.kind, EpisodeTargetOneOf1KindEnum.create);

      // No metadata anywhere → empty list → the apply request leaves
      // episode_groups ABSENT (byte-identical single-episode flow).
      const flat = AiApplyState(
        rows: [PreviewRow(draftRef: 'd1', label: 'A')],
      );
      expect(flat.buildEpisodeGroups(), isEmpty);
    });
  });

  group('Apply round-trip against a fake (task 4.3)', () {
    late CacheDatabase db;
    late FakeAiImportRepository repo;
    late ProviderContainer container;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = FakeAiImportRepository(BreakdownApi(), AiImportJobsCacheDao(db));
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    Future<Result<ApplyAiImportResponse>> seedAndApply() async {
      final controller = container.read(
        aiApplyControllerProvider('job-1').notifier,
      );
      controller.seedRows(const [
        PreviewRow(draftRef: 'd1', label: 'A'),
        PreviewRow(draftRef: 'd2', label: 'B'),
      ], const AiJobContext(episodeId: 'ep-1', projectId: 'series-1'));
      return controller.apply();
    }

    test('immediate 200 → the outcome summary', () async {
      repo.applyQueue.add(Right(_outcome()));
      final res = await seedAndApply();
      expect(res.getRight().toNullable()!.appliedCount, 2);
      // The request echoed the controller-built payload.
      expect(repo.lastRequest!.episodeId, 'ep-1');
    });

    test(
      'definitive 403 surfaces immediately (no retry, no re-read)',
      () async {
        repo.applyQueue.add(
          const Left(ProblemError(code: 'ai-import.forbidden', status: 403)),
        );
        final res = await seedAndApply();
        expect(res.getLeft().toNullable()!.code, 'ai-import.forbidden');
        expect(repo.applyRequests, hasLength(1));
      },
    );

    test('ambiguous timeout re-reads the job FIRST, then bounded-retries '
        '(server-side idempotency — never a blind re-dispatch)', () async {
      repo.applyQueue.addAll([
        const Left(ProblemError(code: 'transport.connectionTimeout')),
        Right(_outcome(appliedCount: 1)),
      ]);
      repo.jobResult = Right(_succeededJob('job-1'));
      final res = await seedAndApply();
      expect(res.getRight().toNullable()!.appliedCount, 1);
      // Request order: apply → job re-read → apply.
      expect(repo.applyRequests, hasLength(2));
    });
  });

  group('Episode context (task 4.3 — fresh-job AND remembered-job entry)', () {
    late CacheDatabase db;
    late AiImportJobsCacheDao dao;
    late ProviderContainer container;

    setUp(() async {
      db = CacheDatabase(NativeDatabase.memory());
      dao = AiImportJobsCacheDao(db);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(
            FakeAiImportRepository(BreakdownApi(), dao),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
      await container.read(authSessionControllerProvider.notifier).signIn();
    });

    test('remembered-job entry: the persisted context is read from the '
        'job record, never from the navigation stack', () async {
      await dao.upsertWithEpisodeContext(
        _succeededJob('job-1'),
        DateTime.utc(2026, 1, 1),
        episodeId: 'ep-1',
        projectId: 'series-1',
      );
      final context = await container.read(
        aiJobContextProvider('job-1').future,
      );
      expect(context!.episodeId, 'ep-1');
      expect(context.projectId, 'series-1');
    });

    test('missing context (a job id from an older build) → the picker is '
        'REQUIRED; apply never dispatches a guessed episode_id', () async {
      await dao.upsertAll([_succeededJob('job-2')], DateTime.utc(2026, 1, 1));
      final context = await container.read(
        aiJobContextProvider('job-2').future,
      );
      expect(context, isNull);
    });
  });

  group('Preview + apply widget tests (task 4.4)', () {
    late CacheDatabase db;
    late FakeAiImportRepository repo;
    late AiImportJobsCacheDao dao;
    late ValueNotifier<Result<AiImportPreviewResponse>> preview;
    late ValueNotifier<Result<List<SceneView>>> scenes;
    late ProviderContainer container;

    Future<void> setupContainer({
      Result<AiImportPreviewResponse>? previewValue,
      Result<List<SceneView>>? scenesValue,
      bool withPersistedContext = true,
      List<Result<ApplyAiImportResponse>>? applyQueue,

      /// Overrides [cacheDatabaseProvider] so the episode-picker's legacy
      /// cache-wide fallback reads THIS test's in-memory Drift (the test
      /// seeds rows via [EpisodeCacheDao] after setup).
      bool withCacheDatabase = false,

      /// The configured-naming fixture the naming line renders (issue
      /// #608); `false` exercises the honest unconfigured degradation.
      bool naming = true,
    }) async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      dao = AiImportJobsCacheDao(db);
      repo = FakeAiImportRepository(BreakdownApi(), dao);
      if (applyQueue != null) repo.applyQueue.addAll(applyQueue);
      preview = ValueNotifier(
        previewValue ?? Right(_previewResponse(_scriptPayload())),
      );
      scenes = ValueNotifier(scenesValue ?? Right([_scene('sc-9')]));
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
          aiPreviewProvider.overrideWith((ref, jobId) async => preview.value),
          aiJobContextProvider.overrideWith((ref, jobId) async {
            if (!withPersistedContext) return null;
            return const AiJobContext(episodeId: 'ep-1', projectId: 'series-1');
          }),
          scenesListFetchProvider.overrideWith((ref, episodeId) async {
            return scenes.value;
          }),
          if (withCacheDatabase) cacheDatabaseProvider.overrideWithValue(db),
          // The preview + apply screens render the configured naming line
          // (issue #608) — a deterministic override keeps the tests off
          // the real discovery path and the goldens stable.
          configuredAiNamingProvider.overrideWith(
            (ref) => Future.value(naming ? _namingConfig() : null),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
      if (withPersistedContext) {
        await dao.upsertWithEpisodeContext(
          _succeededJob('job-1'),
          DateTime.utc(2026, 1, 1),
          episodeId: 'ep-1',
          projectId: 'series-1',
        );
      }
    }

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
      // Seed is fire-and-forget; pump until the rows land.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('script preview renders typed rows + uncertainties; the '
        'missing-context path requires the explicit episode pick (apply '
        'disabled)', (tester) async {
      await setupContainer(withPersistedContext: false);
      await pumpPreview(tester);

      expect(find.text('Script preview'), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-row-draft-1')), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-row-draft-2')), findsOneWidget);
      // The uncertainty is an info row (excluded from the decisions).
      expect(find.textContaining('Uncertainty (location)'), findsOneWidget);
      // The apply section: the missing-context notice + disabled button.
      expect(find.byKey(const Key('ai-apply-context-missing')), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.byKey(const Key('ai-apply-submit')),
      );
      expect(apply.onPressed, isNull);
      await tester.pump();
    });

    testWidgets('the preview + apply section name the configured '
        'provider/model and carry the collapsible EU AI Act panel '
        '(issue #608)', (tester) async {
      await setupContainer();
      await pumpPreview(tester);

      // The preview's labelling line: configured wire naming.
      final previewNaming = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('ai-preview-naming')),
              matching: find.byType(Text),
            ),
          )
          .data;
      expect(previewNaming, contains('openai'));
      expect(previewNaming, contains('assistant-model-1'));

      // The apply section's labelling line + collapsed Act panel.
      expect(find.byKey(const Key('ai-apply-naming')), findsOneWidget);
      final panel = find.byKey(const Key('ai-apply-act-panel'));
      expect(panel, findsOneWidget);
      // Collapsed by default: the full body is hidden behind the
      // affordance (compact review section — no layout regression: the
      // review checkbox and submit stay in place below).
      expect(find.byKey(const Key('ai-apply-act-body')), findsNothing);
      expect(find.byKey(const Key('ai-apply-review-checkbox')), findsOneWidget);
      expect(find.byKey(const Key('ai-apply-submit')), findsOneWidget);

      await tester.tap(panel);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('ai-apply-act-body')),
        findsOneWidget,
        reason: 'expanding the panel reveals the full Art. 4/Art. 50 copy',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('ai-apply-act-body'))).data,
        contains('2024/1689'),
      );
    });

    testWidgets('the naming lines degrade honestly when AI is '
        'unconfigured (never an invented name) (issue #608)', (tester) async {
      await setupContainer(naming: false);
      await pumpPreview(tester);

      const degraded = 'No AI configuration is set up for this account.';
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('ai-preview-naming')),
                matching: find.byType(Text),
              ),
            )
            .data,
        degraded,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('ai-apply-naming')),
                matching: find.byType(Text),
              ),
            )
            .data,
        degraded,
      );
    });

    testWidgets('merged preview: matched rows actionable; unmatched rows '
        'render as excluded info cards (no silent coercion)', (tester) async {
      await setupContainer(
        previewValue: Right(_previewResponse(_mergedPayload())),
      );
      await pumpPreview(tester);

      expect(find.text('Merged preview'), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-row-sc-1')), findsOneWidget);
      expect(
        find.textContaining('Unmatched schedule row: row-x'),
        findsOneWidget,
      );
      // Only the matched row carries a decision control.
      expect(find.byKey(const Key('ai-row-decision-sc-1')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('pre-merge schedule preview: informative rows only (no '
        'decision chips)', (tester) async {
      await setupContainer(
        previewValue: Right(_previewResponse(_preMergePayload())),
      );
      await pumpPreview(tester);

      expect(find.text('Schedule preview (pre-merge)'), findsOneWidget);
      expect(find.byKey(const Key('ai-row-decision-row-1')), findsNothing);
      await tester.pump();
    });

    testWidgets('unknown future kind strict-rejects with the stable '
        'degraded card (no guessed rendering)', (tester) async {
      await setupContainer(
        previewValue: const Left(
          ProblemError(code: 'ai_import.preview_kind_unknown'),
        ),
      );
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-kind-unknown')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('empty preview (404) renders the explicit no-preview state', (
      tester,
    ) async {
      await setupContainer(
        previewValue: const Left(
          ProblemError(code: 'ai_import.preview_missing', status: 404),
        ),
      );
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-missing')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('the AI-extracted banner precedes the typed payload; the '
        'degraded card does NOT carry it (issue #538)', (tester) async {
      await setupContainer();
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-ai-banner')), findsOneWidget);
      // The honest review note (no machine-verified confidence values) —
      // never fabricated per-row confidence chips (the wire has none).
      expect(find.textContaining('machine-extracted draft'), findsOneWidget);
      final bannerY = tester
          .getTopLeft(find.byKey(const Key('ai-preview-ai-banner')))
          .dy;
      final headerY = tester
          .getTopLeft(find.byKey(const Key('ai-preview-title')))
          .dy;
      expect(
        bannerY < headerY,
        isTrue,
        reason: 'the AI framing precedes the payload header in scroll order',
      );
    });

    testWidgets('a REFRESHED preview drops the review acknowledgement: the '
        'replacement rows cannot be applied unreviewed (issue #538 review)', (
      tester,
    ) async {
      await setupContainer(applyQueue: [Right(_outcome())]);
      await pumpPreview(tester);

      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('ai-apply-submit')));

      // Acknowledge the CURRENT payload and dispatch it.
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);

      // A provider refresh replaces the payload with DIFFERENT rows at the
      // same element position (the unkeyed AiApplySection is reused). The
      // stale acknowledgement must not carry over to the new content.
      preview.value = Right(
        _previewResponse(
          AiPreviewPayload(
            (b) => b
              ..oneOf =
                  OneOf.fromValue3<
                    AiPreviewPayloadOneOf,
                    AiPreviewPayloadOneOf1,
                    AiPreviewPayloadOneOf2
                  >(
                    value: AiPreviewPayloadOneOf(
                      (b2) => b2
                        ..kind = AiPreviewPayloadOneOfKindEnum.script
                        ..data.replace(
                          ScriptContext(
                            (b3) => b3
                              ..scenes.replace([
                                _draft('fresh-1'),
                                _draft('fresh-2'),
                                _draft('fresh-3'),
                              ])
                              ..uncertainties.replace([]),
                          ),
                        ),
                    ),
                  ),
          ),
        ),
      );
      container.invalidate(aiPreviewProvider);
      await pumpPreview(tester);

      // The fresh rows seeded…
      expect(
        container.read(aiApplyControllerProvider('job-1')).rows,
        hasLength(3),
      );
      // …but the acknowledgement was reset: the dispatch is gated again.
      expect(
        submit().onPressed,
        isNull,
        reason: 'a replacement payload needs its own review acknowledgement',
      );
      expect(find.byKey(const Key('ai-apply-review-checkbox')), findsOneWidget);
      // Re-acknowledging unlocks exactly one further dispatch.
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull);
    });

    testWidgets('apply review acknowledgement: unchecked disabled, checked '
        'dispatches (issue #538)', (tester) async {
      await setupContainer(applyQueue: [Right(_outcome())]);
      await pumpPreview(tester);
      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('ai-apply-submit')));
      expect(
        submit().onPressed,
        isNull,
        reason: 'context valid but the review ack is unchecked — disabled',
      );
      expect(find.byKey(const Key('ai-apply-review-checkbox')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      expect(
        submit().onPressed,
        isNotNull,
        reason: 'acknowledged — the single dispatch unlocks',
      );
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      // Acknowledgement adds no second dispatch: exactly one apply call.
      expect(repo.applyRequests, hasLength(1));
    });

    testWidgets('a null oneOf value renders the degraded card — never a '
        'build-time cast throw (review: OneOf.value is nullable)', (
      tester,
    ) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            AiPreviewPayload(
              (b) => b
                ..oneOf =
                    OneOf.fromValue3<
                      AiPreviewPayloadOneOf,
                      AiPreviewPayloadOneOf1,
                      AiPreviewPayloadOneOf2
                    >(value: null, typeIndex: 0),
            ),
          ),
        ),
      );
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-kind-unknown')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('a refreshed payload RE-SEEDS the apply rows (review: '
        'stale draft_refs after a provider refresh)', (tester) async {
      await setupContainer(withPersistedContext: true);
      await pumpPreview(tester);
      expect(
        container.read(aiApplyControllerProvider('job-1')).rows,
        hasLength(2),
        reason: 'the script payload seeds two draft rows',
      );

      // The provider refresh delivers a NEW response at the SAME element
      // position — the seed must follow the payload identity.
      preview.value = Right(
        _previewResponse(
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
                              ..title = 'Pilot (refreshed)'
                              ..scenes.replace([
                                _draft('draft-1'),
                                _draft('draft-2'),
                                _draft('draft-3'),
                              ])
                              ..uncertainties.replace([]),
                          ),
                        ),
                    ),
                  ),
          ),
        ),
      );
      container.invalidate(aiPreviewProvider);
      await pumpPreview(tester);

      // The refreshed row renders AND the apply rows followed (3 rows,
      // incl. the new draft-3) — never the stale 2-row seed.
      expect(find.byKey(const Key('ai-preview-row-draft-3')), findsOneWidget);
      expect(
        container.read(aiApplyControllerProvider('job-1')).rows,
        hasLength(3),
      );
      expect(
        container
            .read(aiApplyControllerProvider('job-1'))
            .rows
            .map((r) => r.draftRef),
        contains('draft-3'),
      );
      await tester.pump();
    });

    testWidgets('mixed decisions: Create + Update-from-picked + skip; the '
        'apply 200 renders the outcome summary', (tester) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
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
                                ..scenes.replace([
                                  _draft('draft-1'),
                                  _draft('draft-2'),
                                  _draft('draft-3'),
                                ])
                                ..uncertainties.replace(
                                  BuiltList(const <Uncertainty>[]),
                                ),
                            ),
                          ),
                      ),
                    ),
            ),
          ),
        ),
        applyQueue: [Right(_outcome())],
      );
      await pumpPreview(tester);

      // Mark draft-2 as Update (picker over the episode's existing
      // aggregates, ids + versions from the read DTOs).
      await tester.tap(find.byKey(const Key('ai-row-decision-draft-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-scene-pick-sc-9')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('ai-preview-row-picked-draft-2')),
        findsOneWidget,
      );
      // Skip draft-3.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('ai-row-decision-draft-3')),
          matching: find.text('Skip'),
        ),
      );
      await tester.pumpAndSettle();

      // NEW (issue #538): the acknowledgement gates the dispatch.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-apply-submit')))
            .onPressed,
        isNull,
        reason: 'the dispatch stays gated until the ack is checked',
      );
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
      expect(find.textContaining('Applied 2 draft(s)'), findsOneWidget);
      // The request carried exactly the acted-on rows.
      expect(repo.lastRequest!.mappings, hasLength(2));
      await tester.pump();
    });

    testWidgets('apply 403 renders the localized narrative', (tester) async {
      await setupContainer(
        applyQueue: [
          const Left(ProblemError(code: 'ai-import.forbidden', status: 403)),
        ],
      );
      await pumpPreview(tester);
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You do not have access to this AI import job'),
        findsOneWidget,
      );
      await tester.pump();
    });

    testWidgets('apply not-succeeded (409-class) renders the job-status '
        'path copy', (tester) async {
      await setupContainer(
        applyQueue: [
          const Left(
            ProblemError(
              code: 'ai_import.apply_job_not_succeeded',
              status: 409,
            ),
          ),
        ],
      );
      await pumpPreview(tester);
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('check the job status'), findsOneWidget);
      await tester.pump();
    });

    // Task 7.4 (`ai-import` — the reviewer sees the extraction, its evidence,
    // and can veto it per row).
    testWidgets('a draft row with costumes lists them with their grounding '
        'quote, all accepted by default', (tester) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            _scriptPayloadWith([
              _draft(
                'draft-1',
                costumes: [
                  _costume('Renee Sanders', 'blue linen dress'),
                  _costume(
                    'Renee Sanders',
                    'leather coat',
                    quote: 'greift zum Ledermantel',
                  ),
                ],
              ),
            ]),
          ),
        ),
      );
      await pumpPreview(tester);

      expect(find.text('Costumes (2)'), findsOneWidget);
      expect(find.text('Renee Sanders: blue linen dress'), findsOneWidget);
      // The quote is visible NEXT TO the description so the reviewer can verify
      // the extraction without opening the document (spec `ai-import`).
      expect(find.text('Source: greift zum Ledermantel'), findsOneWidget);
      // Default state: both accepted, so no rejection marker anywhere.
      for (final ordinal in [0, 1]) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(Key('ai-preview-costume-toggle-draft-1-$ordinal')),
              )
              .value,
          isTrue,
        );
        expect(
          find.byKey(Key('ai-preview-costume-rejected-draft-1-$ordinal')),
          findsNothing,
        );
      }
    });

    testWidgets('rejecting ONE costume leaves the scene decision Create and '
        'marks only that costume rejected', (tester) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            _scriptPayloadWith([
              _draft(
                'draft-1',
                costumes: [
                  _costume('Renee Sanders', 'blue linen dress'),
                  _costume('Renee Sanders', 'leather coat'),
                ],
              ),
            ]),
          ),
        ),
        applyQueue: [
          Right(
            _outcome(
              appliedCount: 1,
              createdDays: 0,
              plannedSceneShoots: 0,
              createdCharacters: 1,
              createdCostumes: 1,
            ),
          ),
        ],
      );
      await pumpPreview(tester);

      await tester.tap(
        find.byKey(const Key('ai-preview-costume-toggle-draft-1-1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ai-preview-costume-rejected-draft-1-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-preview-costume-rejected-draft-1-0')),
        findsNothing,
        reason: 'the veto is per costume row, not per scene',
      );
      // The scene row itself is still a Create (the costume veto did not touch
      // it) — the row stays actionable and accept_as_is is gone.
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-row-decision-draft-1')),
          matching: find.text('Create'),
        ),
        findsOneWidget,
      );
      final state = container.read(aiApplyControllerProvider('job-1'));
      expect(state.acceptAsIs, isFalse);
      expect(state.editDistance, 1);

      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      // Only the REJECTED ordinal travels; the accepted one stays absent and
      // reads as accepted server-side.
      final mapping = repo.lastRequest!.mappings.single;
      expect(mapping.draftRef, 'draft-1');
      expect(mapping.costumeDecisions, hasLength(1));
      expect(mapping.costumeDecisions!.single.ordinal, 1);
      expect(mapping.costumeDecisions!.single.accepted, isFalse);
      // The scene was still created: the veto never drops the row.
      expect(mapping.decision.oneOf.value, 'Create');
    });

    testWidgets('a costume the apply could not bind is NAMED with a localized '
        'reason — a partial apply never reads as a full one', (tester) async {
      await setupContainer(
        applyQueue: [
          Right(
            _outcome(
              appliedCount: 1,
              createdDays: 0,
              plannedSceneShoots: 0,
              createdCharacters: 1,
              createdCostumes: 1,
              unappliedCostumes: [
                UnappliedCostume(
                  (b) => b
                    ..draftRef = 'draft-1'
                    ..ordinal = 2
                    ..characterName = 'Renee Sanders'
                    ..description = 'wedding dress'
                    ..reason = UnappliedCostumeReason.bindingRejected,
                ),
              ],
            ),
          ),
        ],
      );
      await pumpPreview(tester);
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
      // The script wording reports the figures/costumes it produced.
      expect(
        find.textContaining('Applied 1 scene(s), 1 character(s), 1 costume(s)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Not applied: Renee Sanders – wedding dress'),
        findsOneWidget,
      );
      // Keyed on the typed wire enum, not on server prose.
      expect(
        find.textContaining('costume created, binding refused (unassigned)'),
        findsOneWidget,
      );
    });

    testWidgets('a costume the server DROPPED is visible as an uncertainty row '
        'and does NOT gate the apply (design D8)', (tester) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            _scriptPayloadWith(
              [_draft('draft-1')],
              uncertainties: [
                Uncertainty(
                  (u) => u
                    ..sceneIndex = 1
                    ..field = 'costumes'
                    // The exact note shape the worker writes (design D8): the
                    // stable reason slug first, then the dropped entry.
                    ..note =
                        'ungrounded_quote: costume of "Renee" '
                        '("ball gown") was dropped; row draft-1'
                    ..kind = UncertaintyKind.droppedRow,
                ),
              ],
            ),
          ),
        ),
      );
      await pumpPreview(tester);

      // The reviewer sees the MISSING entry (the note carries the stable reason
      // slug) instead of concluding the script named no costuming.
      expect(find.textContaining('Uncertainty (costumes)'), findsOneWidget);
      expect(find.textContaining('ungrounded_quote'), findsOneWidget);
      // `droppedRow` is information, not a gate: the apply stays dispatchable.
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-apply-submit')))
            .onPressed,
        isNotNull,
        reason: 'a dropped costume row must not block the whole import',
      );
    });

    testWidgets('script rows render GROUPED by draft episode with per-group '
        'targets; unmarked rows fall back to the picked target (issue #581)', (
      tester,
    ) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            _scriptPayloadWith([
              _draft('d1', episode: _episodeMeta(3, 'Titel')),
              _draft('d2', episode: _episodeMeta(3, 'Titel')),
              _draft('d3', episode: _episodeMeta(5, null)),
              _draft('d4'),
            ]),
          ),
        ),
      );
      await pumpPreview(tester);

      // Group headers in document order: one per group-run, labelled from
      // the Ep.: marker, with the seeded create-new target.
      expect(
        find.byKey(const Key('ai-preview-group-header-ep:3')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-preview-group-header-ep:3')),
          matching: find.text('Episode 3 \u00b7 Titel'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-preview-group-header-ep:3')),
          matching: find.text('Create new: Episode 3 \u00b7 Titel'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-preview-group-header-ep:5')),
        findsOneWidget,
      );
      // Unmarked rows: the ungrouped header names the explicitly picked
      // target episode — no selector there.
      expect(
        find.byKey(const Key('ai-preview-ungrouped-header')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-preview-ungrouped-header')),
          matching: find.text('No episode marker — target: episode ep-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-preview-group-target-change-ep:5')),
        findsOneWidget,
        reason: 'grouped rows carry the target selector',
      );
      expect(
        find.byKey(const Key('ai-preview-group-target-change-ungrouped')),
        findsNothing,
      );

      // The apply card summarizes each group's target at the dispatch
      // point (EU AI Act review gate).
      expect(
        find.byKey(const Key('ai-apply-group-target-ep:3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-apply-group-target-ep:5')),
        findsOneWidget,
      );

      // Every seeded target carries its number → apply unlocks with the
      // review acknowledgement.
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('ai-apply-submit')),
      );
      expect(submit.onPressed, isNotNull);
      await tester.pump();
    });

    testWidgets('a title-only group gates the dispatch until the reviewer '
        'enters the wire-required number; the create editor pre-fills the '
        'heading and the dispatch carries episode_groups (issue #581)', (
      tester,
    ) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            _scriptPayloadWith([
              _draft('d1', episode: _episodeMeta(null, 'Sommer')),
            ]),
          ),
        ),
        applyQueue: [Right(_outcome(createdEpisodes: 1))],
      );
      await pumpPreview(tester);
      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('ai-apply-submit')));

      // The marker had no number → the create target is incomplete → the
      // dispatch stays disabled even WITH the review acknowledgement.
      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      expect(
        submit().onPressed,
        isNull,
        reason:
            'a create target without its wire-required number must not '
            'dispatch',
      );

      // The create editor: number empty, name pre-filled from the heading.
      await tester.tap(
        find.byKey(const Key('ai-preview-group-target-change-ep-t:Sommer')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-group-target-create')));
      await tester.pumpAndSettle();
      final nameField = tester.widget<TextFormField>(
        find.byKey(const Key('ai-group-create-name')),
      );
      expect(nameField.controller!.text, 'Sommer');

      // An invalid number keeps the dialog open with its validation copy.
      await tester.enterText(
        find.byKey(const Key('ai-group-create-number')),
        'abc',
      );
      await tester.tap(find.byKey(const Key('ai-group-create-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-group-create-dialog')), findsOneWidget);

      // A valid number closes the dialog, updates the target and unlocks
      // the dispatch (the acknowledgement is already checked).
      await tester.enterText(
        find.byKey(const Key('ai-group-create-number')),
        '7',
      );
      await tester.tap(find.byKey(const Key('ai-group-create-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-group-create-dialog')), findsNothing);
      expect(submit().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      // The wire: one group with kind create + the entered number and the
      // heading's name; the group edit counted into edit_distance.
      final groups = repo.lastRequest!.episodeGroups!;
      expect(groups, hasLength(1));
      expect(groups.single.episodeRef, 'ep-t:Sommer');
      final target = groups.single.target.oneOf.value as EpisodeTargetOneOf1;
      expect(target.number, 7);
      expect(target.name, 'Sommer');
      expect(target.kind, EpisodeTargetOneOf1KindEnum.create);
      expect(repo.lastRequest!.editDistance, 1);
      expect(repo.lastRequest!.acceptAsIs, isFalse);
    });

    testWidgets('switching a group to an EXISTING episode picks from the read '
        'DTOs and sends kind existing (issue #581)', (tester) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            _scriptPayloadWith([
              _draft('d1', episode: _episodeMeta(3, 'Titel')),
            ]),
          ),
        ),
        applyQueue: [Right(_outcome())],
        withCacheDatabase: true,
      );
      // Seed the cache the picker's legacy cache-wide fallback reads (the
      // job fixture carries no block scope).
      await EpisodeCacheDao(db)
          .upsert(_cachedEpisode('ep-9'), DateTime.utc(2026, 1, 1));
      await pumpPreview(tester);

      await tester.tap(
        find.byKey(const Key('ai-preview-group-target-change-ep:3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-group-target-pick-existing')));
      await tester.pumpAndSettle();
      // The picker lists the cached episode; ids come from the read DTO.
      await tester.tap(find.byKey(const Key('ai-episode-pick-ep-9')));
      await tester.pumpAndSettle();

      // The group header's target label AND the apply card's summary line
      // both reflect the pick.
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-preview-group-header-ep:3')),
          matching: find.text('Existing episode: Episode 2'),
        ),
        findsOneWidget,
      );
      final summary = tester.widget<Text>(
        find.byKey(const Key('ai-apply-group-target-ep:3')),
      );
      expect(summary.data, contains('Existing episode: Episode 2'));

      await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();

      final groups = repo.lastRequest!.episodeGroups!;
      expect(groups, hasLength(1));
      expect(groups.single.episodeRef, 'ep:3');
      final target = groups.single.target.oneOf.value as EpisodeTargetOneOf;
      expect(target.episodeId, 'ep-9');
      expect(target.kind, EpisodeTargetOneOfKindEnum.existing);
    });

    group('goldens (4.4): merged preview {light,dark}×{android,macos}', () {
      Future<void> pumpGolden(
        WidgetTester tester, {
        required String golden,
        required ThemeMode mode,
        required TargetPlatform platform,
      }) async {
        try {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData.light(),
                darkTheme: ThemeData.dark(),
                themeMode: mode,
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

      testWidgets('merged golden light android', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_light_android.png',
          mode: ThemeMode.light,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('merged golden dark android', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_dark_android.png',
          mode: ThemeMode.dark,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('merged golden light macos', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_light_macos.png',
          mode: ThemeMode.light,
          platform: TargetPlatform.macOS,
        );
      });

      testWidgets('merged golden dark macos', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_dark_macos.png',
          mode: ThemeMode.dark,
          platform: TargetPlatform.macOS,
        );
      });
    });
  });
}

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}
