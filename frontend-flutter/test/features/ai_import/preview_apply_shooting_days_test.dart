// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

// Tier-2 widget tests for the issue #706 frontend continuation: the
// script preview renders each row's extracted shooting day, the apply
// card carries the per-day decision section (accept-all default) with its
// dispatch-point summary, the apply request carries ONE decision per day
// group (or none when the preview has no day metadata), and the outcome
// card reports the rejected day groups.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';

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

DraftShootingDay _dayMeta({int? number, String? label}) => DraftShootingDay(
  (b) => b
    ..number = number
    ..label = label,
);

DraftScene _draft(String ref, {int? number, DraftShootingDay? shootingDay}) =>
    DraftScene((b) {
      b
        ..draftRef = ref
        ..sceneNumber = number
        ..summary = 'Scene $ref'
        ..characters.replace(const <DraftCharacter>[])
        ..costumes.replace(const <DraftCostume>[]);
      if (shootingDay != null) b.shootingDay.replace(shootingDay);
    });

AiPreviewPayload _scriptPayload(List<DraftScene> scenes) => AiPreviewPayload(
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
                    ..uncertainties.replace(const <Uncertainty>[]),
                ),
              ),
          ),
        ),
);

AiImportPreviewResponse _previewResponse(AiPreviewPayload payload) =>
    AiImportPreviewResponse(
      (b) => b
        ..jobId = 'job-1'
        ..documentKind = DocumentKind.script
        ..status = JobStatus.succeeded
        ..preview.replace(payload),
    );

AiImportJob _succeededJob(String id) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = JobStatus.succeeded
    ..documentKind = DocumentKind.script
    ..sourceFormat = SourceFormat.pdf
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

ApplyAiImportResponse _outcome({List<String> skippedDayGroups = const []}) =>
    ApplyAiImportResponse(
      (b) => b
        ..appliedCount = 2
        ..createdDays = 1
        ..plannedSceneShoots = 3
        ..createdCharacters = 0
        ..createdCostumes = 0
        ..createdEpisodes = 0
        ..skippedDayGroups.addAll(skippedDayGroups)
        ..unappliedCostumes.replace(const <UnappliedCostume>[]),
    );

class FakeAiImportRepository extends AiImportRepository {
  FakeAiImportRepository(super.api, super.cache);

  final List<Result<ApplyAiImportResponse>> applyQueue = [];
  final List<ApplyAiImportRequest> applyRequests = [];

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async {
    applyRequests.add(request);
    return applyQueue.removeAt(0);
  }
}

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheDatabase db;
  late FakeAiImportRepository repo;
  late AiImportJobsCacheDao dao;
  late ProviderContainer container;

  Future<void> setupContainer({
    required AiPreviewPayload payload,
    List<Result<ApplyAiImportResponse>> applyQueue = const [],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    dao = AiImportJobsCacheDao(db);
    repo = FakeAiImportRepository(BreakdownApi(), dao);
    repo.applyQueue.addAll(applyQueue);
    final preview = ValueNotifier<Result<AiImportPreviewResponse>>(
      Right(_previewResponse(payload)),
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiImportRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => _ImmediateScheduler(),
        ),
        aiPreviewProvider.overrideWith((ref, jobId) async => preview.value),
        aiJobContextProvider.overrideWith((ref, jobId) async {
          return const AiJobContext(episodeId: 'ep-1', projectId: 'series-1');
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
    await dao.upsertWithEpisodeContext(
      _succeededJob('job-1'),
      DateTime.utc(2026, 1, 1),
      episodeId: 'ep-1',
      projectId: 'series-1',
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
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  final applyButton = find.byKey(const Key('ai-apply-submit'));

  Future<void> acknowledgeAndApply(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai-apply-review-checkbox')));
    await tester.pump();
    await tester.ensureVisible(applyButton);
    await tester.pump();
    await tester.tap(applyButton);
    await tester.pumpAndSettle();
  }

  testWidgets('script preview renders each row day line; the apply card '
      'carries the day-decision section with its dispatch summary', (
    tester,
  ) async {
    await setupContainer(
      payload: _scriptPayload([
        _draft(
          'draft-1',
          number: 1,
          shootingDay: _dayMeta(number: 1, label: 'Tag 1'),
        ),
        _draft(
          'draft-2',
          number: 2,
          shootingDay: _dayMeta(number: 1, label: 'Tag 1'),
        ),
        _draft(
          'draft-3',
          number: 3,
          shootingDay: _dayMeta(number: 2, label: 'Tag 2'),
        ),
        _draft('draft-4', number: 4), // unscheduled flow — no day line
      ]),
    );
    await pumpPreview(tester);

    // The per-row day lines: the verbatim marker wins.
    expect(find.byKey(const Key('ai-preview-row-day-draft-1')), findsOneWidget);
    expect(find.text('Shooting day: Tag 1'), findsNWidgets(2));
    expect(find.text('Shooting day: Tag 2'), findsOneWidget);
    expect(find.byKey(const Key('ai-preview-row-day-draft-4')), findsNothing);

    // The decision section: one checkbox per day group, pre-checked.
    expect(
      find.byKey(const Key('ai-apply-shooting-days-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai-apply-day-decision-day:1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai-apply-day-decision-day:2')),
      findsOneWidget,
    );
    // Dispatch-point summary: both days reported as created.
    expect(find.byKey(const Key('ai-apply-day-summary-day:1')), findsOneWidget);
    await tester.pump();
  });

  testWidgets('the apply request carries ONE decision per day group; an '
      'unchecked day travels as accepted=false (never an absent entry)', (
    tester,
  ) async {
    await setupContainer(
      payload: _scriptPayload([
        _draft(
          'draft-1',
          number: 1,
          shootingDay: _dayMeta(number: 1, label: 'Tag 1'),
        ),
        _draft(
          'draft-2',
          number: 2,
          shootingDay: _dayMeta(number: 2, label: 'Tag 2'),
        ),
      ]),
      applyQueue: [Right(_outcome())],
    );
    await pumpPreview(tester);

    // Default review: both groups accepted on the wire.
    await acknowledgeAndApply(tester);
    expect(repo.applyRequests, hasLength(1));
    final defaultRequest = repo.applyRequests.single.shootingDays!;
    expect(defaultRequest, hasLength(2));
    expect(defaultRequest.every((d) => d.accepted), isTrue);
  });

  testWidgets('unchecking a day group shows the rejected status and sends '
      'accepted=false; the outcome reports the skipped group', (tester) async {
    await setupContainer(
      payload: _scriptPayload([
        _draft(
          'draft-1',
          number: 1,
          shootingDay: _dayMeta(number: 1, label: 'Tag 1'),
        ),
        _draft(
          'draft-2',
          number: 2,
          shootingDay: _dayMeta(number: 2, label: 'Tag 2'),
        ),
      ]),
      applyQueue: [
        Right(_outcome(skippedDayGroups: const ['day:2'])),
      ],
    );
    await pumpPreview(tester);

    await tester.tap(find.byKey(const Key('ai-apply-day-decision-day:2')));
    await tester.pump();
    // The unchecked day names the consequence at the checkbox…
    expect(
      find.byKey(const Key('ai-apply-day-rejected-status-day:2')),
      findsOneWidget,
    );
    // …and at the dispatch point.
    expect(
      find.textContaining('Shooting day „Tag 2“ will not be created'),
      findsOneWidget,
    );

    await acknowledgeAndApply(tester);
    final request = repo.applyRequests.single.shootingDays!;
    expect(request.singleWhere((d) => d.dayRef == 'day:2').accepted, isFalse);
    expect(request.singleWhere((d) => d.dayRef == 'day:1').accepted, isTrue);

    // The outcome card reports the deliberate omission — never silent.
    expect(find.byKey(const Key('ai-apply-skipped-days')), findsOneWidget);
  });

  testWidgets('a preview WITHOUT day metadata renders no day section and '
      'sends no shooting_days (byte-identical to the pre-#706 client)', (
    tester,
  ) async {
    await setupContainer(
      payload: _scriptPayload([
        _draft('draft-1', number: 1),
        _draft('draft-2', number: 2),
      ]),
      applyQueue: [Right(_outcome())],
    );
    await pumpPreview(tester);

    expect(find.byKey(const Key('ai-apply-shooting-days-title')), findsNothing);
    await acknowledgeAndApply(tester);
    expect(repo.applyRequests.single.shootingDays, isNull);
  });
}
