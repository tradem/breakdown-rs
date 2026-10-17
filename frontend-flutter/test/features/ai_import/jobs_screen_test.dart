// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-1 + Tier-2 tests for the AI-import jobs view (issue #547):
//
// * the list controller's cache-then-revalidate ordering (cached rows
//   paint before the fetch resolves; the fetch replaces them; a failed
//   fetch keeps the retained rows with the error);
// * the wiring-gap proof: `listJobsAndCache` now has a production call
//   site, while the repository watch-call count stays ZERO (D5 — the
//   list arms no watch);
// * the remembered-id fast path (seed ordering) and the `forgetJob`
//   reconciliation against the authoritative list;
// * the pure mappers (unknown future wire status degrades, never
//   guesses) and the code-keyed list-error copy;
// * the jobs screen widget matrix (rows, navigation, empty, error,
//   stale, terminal-failure distinctness) and goldens
//   {light,dark}×{android,macos}.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
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
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_screen.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

import '../../support/fake_secure_storage.dart';

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

AiImportJob _job(
  String id, {
  JobStatus status = JobStatus.pending,
  DocumentKind kind = DocumentKind.schedule,
  int retries = 0,
  int maxRetries = 3,
  String? lastError,
  CostBreakdown? cost,
}) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = status
    ..documentKind = kind
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = retries
    ..maxRetries = maxRetries
    ..lastError = lastError
    ..cost = cost?.toBuilder()
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

/// A `known` cost snapshot fixture (issue #675): token total $0.0235 and —
/// when [withEnergy] — a Neuralwatt-style energy cost of $0.00005 (uncapped
/// by default; the cap flag mirrors the wire shape).
CostBreakdown _knownCost({bool withEnergy = false, bool capped = false}) =>
    CostBreakdown(
      (b) => b
        ..status = CostStatus.known
        ..currency = Currency.USD
        ..priceAsOf = DateTime.utc(2026, 1, 1)
        ..pricingSource = PricingSource.curatedSeed
        ..tokenCost = TokenCostBreakdown(
          (b) => b
            ..tokensIn = 4700
            ..tokensOut = 1200
            ..cachedTokensIn = 0
            ..inputRateNanoPerMillion = 1450000000
            ..outputRateNanoPerMillion = 4000000000
            ..totalNano = 23500000,
        ).toBuilder()
        ..energyCost = withEnergy
            ? EnergyCostBreakdown(
                (b) => b
                  ..energyMillijoules = 1800000
                  ..rateNanoPerKwh = 10000000000
                  ..rawEnergyNano = 50000
                  ..effectiveCappedNano = capped ? 23500000 : 50000
                  ..cappedByTokenCost = capped,
              ).toBuilder()
            : null,
    );

CostBreakdown _unknownCost() =>
    CostBreakdown((b) => b..status = CostStatus.unknown);

CostBreakdown _notApplicableCost() =>
    CostBreakdown((b) => b..status = CostStatus.notApplicable);

/// Repository fake: a scriptable list result (with a pending gate for the
/// cache-first ordering test) and call counters. `readCached` runs the REAL
/// DAO so the seed path exercises the actual Drift read.
class FakeJobsRepository extends AiImportRepository {
  FakeJobsRepository(super.api, super.cache);

  Result<List<AiImportJob>>? listResult;

  /// When set (and not completed), the list fetch parks on this gate —
  /// the cache-first paint is asserted while the fetch is in flight.
  Completer<Result<List<AiImportJob>>>? listGate;

  int listCalls = 0;

  /// MUST stay zero forever: a watch in the list controller is a
  /// regression of D5 (one foreground watch, owned by the status screen).
  int watchCalls = 0;

  /// The delete seam (issue #671): scriptable outcome + call counter.
  Result<void>? deleteResult;
  int deleteCalls = 0;

  @override
  Future<Result<void>> deleteJob(String id) async {
    deleteCalls++;
    final result = deleteResult;
    if (result != null) return result;
    return const Right<ProblemError, void>(null);
  }

  @override
  Future<Result<List<AiImportJob>>> listJobsAndCache({
    Clock clock = Clock.system,
  }) async {
    listCalls++;
    final gate = listGate;
    if (gate != null && !gate.isCompleted) return gate.future;
    return listResult ?? Right<ProblemError, List<AiImportJob>>(const []);
  }

  @override
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = 30,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) {
    watchCalls++;
    return const Stream<Result<AiImportJob>>.empty();
  }
}

/// Lets microtasks (the async seed chain, Riverpod disposal timers) drain
/// without wall-clock gating — a fixed deterministic drain, never a
/// sleep-with-jitter budget.
Future<void> drain([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  CacheDatabase? db;
  FakeJobsRepository? repo;
  ProviderContainer? container;

  Future<void> setupContainer({
    Result<List<AiImportJob>>? listResult,
    Completer<Result<List<AiImportJob>>>? listGate,
    List<Override> overrides = const [],
  }) async {
    final previous = container;
    if (previous != null) previous.dispose();
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db!.close);
    repo = FakeJobsRepository(BreakdownApi(), AiImportJobsCacheDao(db!))
      ..listResult = listResult
      ..listGate = listGate;
    container = ProviderContainer(
      overrides: [
        ...overrides,
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiImportRepositoryProvider.overrideWithValue(repo!),
        // The pushed import-submission screen renders the configured
        // naming line (issue #608) — a deterministic override keeps the
        // test off the real discovery path.
        configuredAiNamingProvider.overrideWith(
          (ref) => Future.value(_namingConfig()),
        ),
      ],
    );
    addTearDown(() {
      try {
        container?.dispose();
      } on StateError {
        // Already disposed by the test body — fine.
      }
    });
    await container!.read(authSessionControllerProvider.notifier).signIn();
  }

  /// Keeps the autoDispose controller mounted for the test's duration —
  /// real screens listen through the selector; a bare `read` would let
  /// Riverpod dispose it before the async seed/reconcile runs.
  ProviderSubscription<AsyncValue<AiImportJobsState>> keepController() {
    final sub = container!.listen(
      aiImportJobsViewControllerProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    return sub;
  }

  group('AiImportJobsViewController — cache-then-revalidate (tier 1)', () {
    test('the fetch seam is the production `listJobsAndCache` call site '
        '(the wiring gap of #547 closes)', () async {
      await setupContainer(
        listResult: Right([_job('job-1', status: JobStatus.running)]),
      );
      final state = await container!.read(aiImportJobsFetchProvider.future);
      expect(state.getRight().toNullable()!.single.id, 'job-1');
      expect(repo!.listCalls, 1);
      container!.dispose();
    });

    test('THE LIST ARMS NO WATCH (D5): the repository watch-call count '
        'stays zero across build, seed and fetch', () async {
      await setupContainer(listResult: Right([_job('job-1')]));
      keepController();
      await drain();
      expect(repo!.watchCalls, 0);
      container!.dispose();
    });

    test('cache-first paint: cached rows (ordered by the remembered-id '
        'fast path) render while the list fetch is still in flight', () async {
      await setupContainer(listGate: Completer<Result<List<AiImportJob>>>());
      // Seed the cache newest-first by updatedAt (DAO ordering)…
      await repo!.cache.upsertAll([
        _job('job-2', status: JobStatus.succeeded),
        _job('job-1', status: JobStatus.running),
      ], DateTime.utc(2026, 1, 1));
      // …and remember job-1 — the fast path paints it FIRST.
      await container!
          .read(aiImportHandoffStoreProvider)
          .rememberJob('dev-user', 'job-1');

      keepController();
      await drain();
      final state = container!.read(aiImportJobsView);
      expect(state.error, isNull);
      expect(state.rows.map((r) => r.id), ['job-1', 'job-2']);
      // The fetch is still parked: the paint is the CACHE, not the list.
      expect(repo!.listCalls, 1);
      container!.dispose();
    });

    test(
      'a remembered id WITHOUT a cached row is skipped — a bare id '
      'cannot drive an honest row (no status/kind/date fabrication)',
      () async {
        await setupContainer(listGate: Completer<Result<List<AiImportJob>>>());
        await repo!.cache.upsertAll([_job('job-2')], DateTime.utc(2026, 1, 1));
        await container!
            .read(aiImportHandoffStoreProvider)
            .rememberJob('dev-user', 'job-9');

        keepController();
        await drain();
        expect(container!.read(aiImportJobsView).rows.map((r) => r.id), [
          'job-2',
        ]);
        container!.dispose();
      },
    );

    test('revalidation: the list fetch replaces the cached paint '
        '(server-authoritative, newest-first)', () async {
      final gate = Completer<Result<List<AiImportJob>>>();
      await setupContainer(listGate: gate);
      await repo!.cache.upsertAll([_job('job-2')], DateTime.utc(2026, 1, 1));

      keepController();
      await drain();
      expect(container!.read(aiImportJobsView).rows.map((r) => r.id), [
        'job-2',
      ]);

      gate.complete(Right([_job('job-3'), _job('job-2')]));
      await drain();
      expect(container!.read(aiImportJobsView).rows.map((r) => r.id), [
        'job-3',
        'job-2',
      ]);
      container!.dispose();
    });

    test(
      'a failed list fetch keeps the retained rows and surfaces the '
      'Err (no silent discard — AGENTS.md §5; never blanks the list)',
      () async {
        final gate = Completer<Result<List<AiImportJob>>>();
        await setupContainer(listGate: gate);
        await repo!.cache.upsertAll([_job('job-2')], DateTime.utc(2026, 1, 1));

        keepController();
        await drain();
        gate.complete(
          const Left(ProblemError(code: 'transport.connectionError')),
        );
        await drain();
        final state = container!.read(aiImportJobsView);
        expect(state.rows.map((r) => r.id), ['job-2']);
        expect(state.isStale, isTrue);
        expect(state.error?.code, 'transport.connectionError');
        container!.dispose();
      },
    );

    test('remembered-id reconciliation: `forgetJob` prunes ids the '
        'authoritative list no longer returns (the fast path\u2019s '
        'documented purpose — first caller in the codebase)', () async {
      await setupContainer(listResult: Right([_job('job-1'), _job('job-2')]));
      final store = container!.read(aiImportHandoffStoreProvider);
      await store.rememberJob('dev-user', 'job-2');
      await store.rememberJob('dev-user', 'job-9');

      keepController();
      await drain();
      final handoff = await store.read('dev-user');
      // job-9 is server-gone → forgotten; job-2 stays remembered.
      expect(handoff.getRight().toNullable()!.jobIds, ['job-2']);
      container!.dispose();
    });

    test('a failed list fetch NEVER forgets remembered ids', () async {
      await setupContainer(
        listResult: const Left(ProblemError(code: 'transport.down')),
      );
      final store = container!.read(aiImportHandoffStoreProvider);
      await store.rememberJob('dev-user', 'job-9');

      keepController();
      await drain();
      final handoff = await store.read('dev-user');
      expect(handoff.getRight().toNullable()!.jobIds, ['job-9']);
      container!.dispose();
    });

    test('pull-to-refresh re-runs exactly the list route', () async {
      await setupContainer(listResult: Right([_job('job-1')]));
      keepController();
      await drain();
      expect(repo!.listCalls, 1);
      await container!
          .read(aiImportJobsViewControllerProvider.notifier)
          .refresh();
      await drain();
      expect(repo!.listCalls, 2);
      expect(repo!.watchCalls, 0);
      container!.dispose();
    });
  });

  group('AiImportJobsViewController — deleteJob (issue #671, tier 1)', () {
    test('a successful delete removes the row optimistically and '
        'reconciles via exactly ONE list re-run', () async {
      await setupContainer(
        listResult: Right([_job('job-d', status: JobStatus.deadLetter)]),
      );
      keepController();
      await drain();
      expect(container!.read(aiImportJobsView).rows.map((r) => r.id), [
        'job-d',
      ]);
      final listCallsBefore = repo!.listCalls;
      // The server no longer knows the job: the reconcile read must not
      // return it (the fake's list result mirrors the post-delete state).
      repo!.listResult = Right(const []);

      final result = await container!
          .read(aiImportJobsViewControllerProvider.notifier)
          .deleteJob('job-d');
      expect(result.isRight(), isTrue);
      expect(repo!.deleteCalls, 1);
      // The reconcile re-runs exactly the list route — no watch (D5).
      expect(repo!.listCalls, listCallsBefore + 1);
      expect(repo!.watchCalls, 0);
      // The deleted row is gone from the view.
      expect(container!.read(aiImportJobsView).rows, isEmpty);
      container!.dispose();
    });

    test('a failed delete rolls the optimistic removal back and '
        'surfaces the error (no silent failure)', () async {
      await setupContainer(
        listResult: Right([_job('job-d', status: JobStatus.deadLetter)]),
      );
      keepController();
      await drain();
      repo!.deleteResult = const Left(
        ProblemError(code: 'ai-import.job-not-deletable'),
      );

      final result = await container!
          .read(aiImportJobsViewControllerProvider.notifier)
          .deleteJob('job-d');
      expect(
        result.getLeft().toNullable()!.code,
        'ai-import.job-not-deletable',
      );
      expect(repo!.deleteCalls, 1);
      // No reconcile read on failure — and the row is back (the server
      // still knows the job).
      expect(repo!.listCalls, 1);
      expect(container!.read(aiImportJobsView).rows.map((r) => r.id), [
        'job-d',
      ]);
      container!.dispose();
    });

    test('isDeletable: dead_letter only — non-terminal and the other '
        'terminal rows carry no delete affordance', () {
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.deadLetter)).isDeletable,
        isTrue,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.pending)).isDeletable,
        isFalse,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.running)).isDeletable,
        isFalse,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.failed)).isDeletable,
        isFalse,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.succeeded)).isDeletable,
        isFalse,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.payloadUnavailable))
            .isDeletable,
        isFalse,
      );
    });
  });

  group('pure mappers + copy (tier 1, no Flutter imports needed)', () {
    test('jobRowViewFromJob maps the DTO fields verbatim', () {
      final view = jobRowViewFromJob(
        _job(
          'job-1',
          status: JobStatus.failed,
          kind: DocumentKind.script,
          retries: 1,
          maxRetries: 4,
          lastError: 'boom',
        ),
      );
      expect(view.status, JobStatus.failed);
      expect(view.documentKind, DocumentKind.script);
      expect(view.retries, 1);
      expect(view.maxRetries, 4);
      expect(view.hasLastError, isTrue);
      expect(view.isTerminalFailure, isFalse);
      expect(view.isInProgress, isTrue);
    });

    test('an unknown future wire status degrades honestly: status null, '
        'raw name kept, unknown copy keyed on the wire value '
        '(the row is never dropped, never guessed)', () {
      final view = jobRowViewFromCacheRow(
        _cacheRow('job-x', statusWire: 'quantum_entangled'),
      );
      expect(view.status, isNull);
      expect(view.statusName, 'quantum_entangled');
      expect(view.statusLabel(AppLocalizationsEn()), contains('unknown'));
      expect(view.isTerminalFailure, isFalse);
      expect(view.needsAttention, isTrue);
    });

    test('the status label matrix covers ALL SIX statuses — including the '
        'two that were unreachable before #547', () {
      final l10n = AppLocalizationsEn();
      for (final (status, needle) in [
        (JobStatus.pending, 'Queued'),
        (JobStatus.running, 'Processing'),
        (JobStatus.succeeded, 'ready'),
        (JobStatus.failed, 'retry is scheduled'),
        (JobStatus.deadLetter, 'gave up'),
        (JobStatus.payloadUnavailable, 'no longer available'),
      ]) {
        final label = jobRowViewFromJob(_job('j', status: status))
            .statusLabel(l10n);
        expect(label, contains(needle), reason: '$status → $label');
        expect(label, isNotEmpty);
      }
    });

    test('needsAttention: every status summons the summary row EXCEPT '
        'succeeded (a silent dead_letter keeps it visible)', () {
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.pending)).needsAttention,
        isTrue,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.running)).needsAttention,
        isTrue,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.failed)).needsAttention,
        isTrue,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.deadLetter))
            .needsAttention,
        isTrue,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.payloadUnavailable))
            .needsAttention,
        isTrue,
      );
      expect(
        jobRowViewFromJob(_job('j', status: JobStatus.succeeded))
            .needsAttention,
        isFalse,
      );
    });

    test('missingRememberedIds: only ids the list no longer carries', () {
      expect(missingRememberedIds(['a', 'b', 'c'], {'a', 'c'}), ['b']);
      expect(missingRememberedIds([], {'a'}), isEmpty);
      expect(missingRememberedIds(['a'], {'a', 'b'}), isEmpty);
    });

    test('seedJobRows: remembered-first order, dedup, bare ids skipped', () {
      final rows = seedJobRows(
        cached: [_cacheRow('job-2'), _cacheRow('job-1'), _cacheRow('job-3')],
        rememberedIds: ['job-1', 'job-9', 'job-2'],
      );
      expect(rows.map((r) => r.id), ['job-1', 'job-2', 'job-3']);
    });

    test('list-error copy is code-keyed, never the server detail', () {
      final l10n = AppLocalizationsEn();
      expect(
        aiJobsListErrorCopy(
          l10n,
          const ProblemError(code: 'ai-import.forbidden'),
        ),
        contains('do not have access'),
      );
      // The client-side no-session pre-gate code shares the narrative.
      expect(
        aiJobsListErrorCopy(l10n, const ProblemError(code: 'authz.denied')),
        contains('do not have access'),
      );
      expect(
        aiJobsListErrorCopy(
          l10n,
          const ProblemError(code: 'ai-import.not-found'),
        ),
        contains('does not exist'),
      );
      expect(
        aiJobsListErrorCopy(
          l10n,
          const ProblemError(code: 'transport.connectionError'),
        ),
        contains('Network problem'),
      );
      expect(
        aiJobsListErrorCopy(
          l10n,
          const ProblemError(code: 'weird.future_code'),
        ),
        contains('weird.future_code'),
      );
    });

    test('aiJobsDeleteErrorCopy is keyed on the stable problem code '
        '(issue #671: the 409 refusal gets its own narrative)', () {
      final l10n = AppLocalizationsEn();
      expect(
        aiJobsDeleteErrorCopy(
          l10n,
          const ProblemError(code: 'ai-import.job-not-deletable'),
        ),
        contains('still being processed'),
      );
      expect(
        aiJobsDeleteErrorCopy(
          l10n,
          const ProblemError(code: 'ai-import.forbidden'),
        ),
        contains('do not have access'),
      );
      expect(
        aiJobsDeleteErrorCopy(
          l10n,
          const ProblemError(code: 'ai-import.not-found'),
        ),
        contains('does not exist'),
      );
      expect(
        aiJobsDeleteErrorCopy(
          l10n,
          const ProblemError(code: 'transport.connectionError'),
        ),
        contains('Network problem'),
      );
      expect(
        aiJobsDeleteErrorCopy(
          l10n,
          const ProblemError(code: 'weird.future_code'),
        ),
        contains('weird.future_code'),
      );
    });
  });

  group('AiImportJobsScreen (tier 2)', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      ThemeMode mode = ThemeMode.light,
      TargetPlatform? platform,
    }) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        if (platform != null) {
          debugDefaultTargetPlatformOverride = platform;
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              locale: const Locale('en'),
              supportedLocales: const [Locale('en'), Locale('de')],
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              // Goldens must be deterministic (AGENTS.md §6): the Karl
              // Kleiderbügel excited wobble is time-driven, so the golden
              // pumps freeze animations — the static excited pose is
              // exactly the remove-animations rendering (spec
              // `flutter-easter-eggs`).
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: const AiImportJobsScreen(),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    }

    testWidgets('rows render kind + date + status text + status icon; '
        'failed rows carry the retry budget; last_error gets a presence '
        'indicator', (tester) async {
      await setupContainer(
        listResult: Right([
          _job('job-r', status: JobStatus.failed, retries: 1, maxRetries: 4),
          _job('job-d', status: JobStatus.deadLetter, lastError: 'boom'),
          _job('job-s', status: JobStatus.succeeded),
        ]),
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-jobs-list')), findsOneWidget);
      // Exact per-row titles: kind + date in the spec's order (regression
      // guard for the gen-l10n parameter order — the generated getter is
      // (date, kind) while the template renders "kind · date").
      for (final id in ['job-r', 'job-d', 'job-s']) {
        final title = tester.widget<Text>(
          find.byKey(Key('ai-jobs-row-title-$id')),
        );
        expect(title.data, 'Schedule · Jan 1, 2026', reason: id);
      }
      expect(find.textContaining('gave up'), findsOneWidget);
      expect(find.textContaining('retry is scheduled'), findsOneWidget);
      expect(find.textContaining('Retry 2 of 5'), findsOneWidget);
      expect(
        find.byKey(const Key('ai-jobs-row-retry-budget-job-r')),
        findsOneWidget,
      );
      // The terminal failure's last_error is a PRESENCE indicator only —
      // the raw server text never renders in the row.
      expect(find.text('boom'), findsNothing);
      expect(
        find.byIcon(Icons.error_outline),
        findsNWidgets(2),
        reason:
            'the failed-row status icon + the dead_letter row last-error '
            'presence indicator',
      );
      // All three status glyphs are distinct per status (the two
      // error_outline instances were asserted above).
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await tester.pump();
    });

    testWidgets('terminal-failure rows are visibly distinct: the '
        'dead_letter icon renders in the error color', (tester) async {
      await setupContainer(
        listResult: Right([
          _job('job-d', status: JobStatus.deadLetter),
          _job('job-s', status: JobStatus.succeeded),
        ]),
      );
      await pumpScreen(tester);

      final deadIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('ai-jobs-row-job-d')),
          matching: find.byIcon(Icons.block),
        ),
      );
      final okIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('ai-jobs-row-job-s')),
          matching: find.byIcon(Icons.check_circle_outline),
        ),
      );
      final errorColor = Theme.of(
        tester.element(find.byKey(const Key('ai-jobs-row-job-d'))),
      ).colorScheme.error;
      expect(deadIcon.color, errorColor);
      expect(okIcon.color, isNot(errorColor));
      await tester.pump();
    });

    testWidgets('dead_letter rows carry the delete affordance → confirm → '
        'the row is gone; non-terminal rows show none (issue #671)', (
      tester,
    ) async {
      await setupContainer(
        listResult: Right([
          _job('job-d', status: JobStatus.deadLetter),
          _job('job-p', status: JobStatus.pending),
        ]),
      );
      await pumpScreen(tester);

      // The affordance exists on the dead_letter row ONLY.
      expect(find.byKey(const Key('ai-jobs-row-delete-job-d')), findsOneWidget);
      expect(find.byKey(const Key('ai-jobs-row-delete-job-p')), findsNothing);

      // Cancel path: the dialog opens, cancel keeps the row, no dispatch.
      await tester.tap(find.byKey(const Key('ai-jobs-row-delete-job-d')));
      await tester.pump();
      expect(find.text('Delete import?'), findsOneWidget);
      expect(find.textContaining('duplicate lock'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-jobs-delete-cancel')));
      await tester.pump();
      expect(find.byKey(const Key('ai-jobs-row-job-d')), findsOneWidget);
      expect(repo!.deleteCalls, 0);

      // Confirm path: the reconcile read no longer returns the row —
      // after the delete the list paints without it.
      await tester.tap(find.byKey(const Key('ai-jobs-row-delete-job-d')));
      await tester.pump();
      repo!.listResult = Right([_job('job-p', status: JobStatus.pending)]);
      await tester.tap(find.byKey(const Key('ai-jobs-delete-confirm')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(repo!.deleteCalls, 1);
      expect(find.byKey(const Key('ai-jobs-row-job-d')), findsNothing);
      expect(find.byKey(const Key('ai-jobs-row-job-p')), findsOneWidget);
    });

    testWidgets('a failed delete restores the row and surfaces the '
        'code-keyed message (no silent failure, issue #671)', (tester) async {
      await setupContainer(
        listResult: Right([_job('job-d', status: JobStatus.deadLetter)]),
      );
      await pumpScreen(tester);
      repo!.deleteResult = const Left(
        ProblemError(code: 'ai-import.job-not-deletable'),
      );

      await tester.tap(find.byKey(const Key('ai-jobs-row-delete-job-d')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-jobs-delete-confirm')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      // The row came back and the refusal message is keyed on the code.
      expect(find.byKey(const Key('ai-jobs-row-job-d')), findsOneWidget);
      expect(find.byKey(const Key('ai-jobs-delete-error')), findsOneWidget);
      expect(find.textContaining('still being processed'), findsOneWidget);
    });

    testWidgets('tapping a row pushes AiJobStatusScreen — the screen that '
        'owns the single watch; the list itself arms none', (tester) async {
      await setupContainer(listResult: Right([_job('job-1')]));
      await pumpScreen(tester);
      expect(repo!.watchCalls, 0);

      await tester.tap(find.byKey(const Key('ai-jobs-row-job-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AiJobStatusScreen), findsOneWidget);
      // The watch call happened exactly ONCE — from the PUSHED status
      // screen's controller, never from the list (before the tap it was
      // zero; the status screen is the single watch owner).
      expect(repo!.watchCalls, 1);
      await tester.pump();
    });

    testWidgets('empty state: honest "no import yet" copy + CTA that '
        'pushes the import entry', (tester) async {
      await setupContainer(listResult: Right(<AiImportJob>[]));
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-jobs-empty')), findsOneWidget);
      expect(find.textContaining('No AI import started yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-jobs-empty-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AiImportSubmitScreen), findsOneWidget);
      await tester.pump();
    });

    testWidgets('error state with no rows: copy keyed on the problem code '
        '(never the server detail) + retry via the list route', (tester) async {
      await setupContainer(
        listResult: const Left(ProblemError(code: 'ai-import.forbidden')),
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-jobs-error')), findsOneWidget);
      expect(find.textContaining('do not have access'), findsOneWidget);
      expect(find.byKey(const Key('ai-jobs-error-retry')), findsOneWidget);
      // The retry re-runs the list route (never a watch).
      await tester.tap(find.byKey(const Key('ai-jobs-error-retry')));
      await tester.pump();
      expect(repo!.listCalls, 2);
      await tester.pump();
    });

    testWidgets('a failed refetch over retained rows: the stale banner '
        'rides on top, the cached list stays (no silent blank)', (
      tester,
    ) async {
      await setupContainer(
        listResult: const Left(ProblemError(code: 'transport.down')),
      );
      await repo!.cache.upsertAll([
        _job('job-2', status: JobStatus.running),
      ], DateTime.utc(2026, 1, 1));
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-jobs-stale-banner')), findsOneWidget);
      expect(find.byKey(const Key('ai-jobs-row-job-2')), findsOneWidget);
      expect(find.textContaining('Processing'), findsOneWidget);
      await tester.pump();
    });

    testWidgets('loading skeleton renders before the first seed '
        '(no cache, no snapshot yet)', (tester) async {
      await setupContainer(listGate: Completer<Result<List<AiImportJob>>>());
      await pumpScreen(tester);
      expect(find.byKey(const Key('ai-jobs-loading')), findsOneWidget);
      await tester.pump();
    });

    group('compact cost line (issue #675, tier 1 + tier 2)', () {
      group('aiJobCostCompactCopy (tier 1)', () {
        test('no snapshot renders nothing', () {
          expect(
            aiJobCostCompactCopy(
              AppLocalizationsEn(),
              null,
              CostDisplayPreference.token,
            ),
            isNull,
          );
        });

        test('known: the token total is the primary figure by default', () {
          expect(
            aiJobCostCompactCopy(
              AppLocalizationsEn(),
              _knownCost(withEnergy: true),
              CostDisplayPreference.token,
            ),
            r'Cost: $0.0235',
          );
        });

        test('known: the energy preference switches the primary figure to '
            'the capped energy cost', () {
          expect(
            aiJobCostCompactCopy(
              AppLocalizationsEn(),
              _knownCost(withEnergy: true),
              CostDisplayPreference.energy,
            ),
            r'Cost: $0.00005',
          );
        });

        test('known without energy: the energy preference falls back to the '
            'token total', () {
          expect(
            aiJobCostCompactCopy(
              AppLocalizationsEn(),
              _knownCost(),
              CostDisplayPreference.energy,
            ),
            r'Cost: $0.0235',
          );
        });

        test('unknown renders the localized Unknown copy — NEVER 0', () {
          final copy = aiJobCostCompactCopy(
            AppLocalizationsEn(),
            _unknownCost(),
            CostDisplayPreference.token,
          )!;
          expect(copy, contains('Unknown'));
          expect(copy.contains('0'), isFalse);
        });

        test('not_applicable renders the no-AI-billed copy', () {
          expect(
            aiJobCostCompactCopy(
              AppLocalizationsEn(),
              _notApplicableCost(),
              CostDisplayPreference.token,
            ),
            'No AI model was billed — native CSV import without an LLM.',
          );
        });
      });

      testWidgets('a known-cost row renders the formatted total in the '
          'list', (tester) async {
        await setupContainer(
          listResult: Right([
            _job('job-c', status: JobStatus.succeeded, cost: _knownCost()),
          ]),
        );
        await pumpScreen(tester);
        expect(find.byKey(const Key('ai-jobs-row-cost-job-c')), findsOneWidget);
        expect(find.textContaining(r'$0.0235'), findsOneWidget);
      });

      testWidgets('an unknown-cost row renders Unknown and never a zero', (
        tester,
      ) async {
        await setupContainer(
          listResult: Right([
            _job('job-u', status: JobStatus.succeeded, cost: _unknownCost()),
          ]),
        );
        await pumpScreen(tester);
        final line = tester.widget<Text>(
          find.byKey(const Key('ai-jobs-row-cost-job-u')),
        );
        expect(line.data, contains('Unknown'));
        expect(line.data!.contains('0'), isFalse);
      });

      testWidgets('a not-applicable row renders the no-AI-billed copy '
          '(native CSV import)', (tester) async {
        await setupContainer(
          listResult: Right([
            _job(
              'job-n',
              status: JobStatus.succeeded,
              cost: _notApplicableCost(),
            ),
          ]),
        );
        await pumpScreen(tester);
        expect(
          find.text(
            'No AI model was billed — native CSV import without an LLM.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Cost:'), findsNothing);
      });

      testWidgets('the energy preference switches the row badge to the '
          'energy figure', (tester) async {
        await setupContainer(
          listResult: Right([
            _job(
              'job-e',
              status: JobStatus.succeeded,
              cost: _knownCost(withEnergy: true),
            ),
          ]),
          overrides: [
            aiCostDisplayPreferenceProvider.overrideWithValue(
              CostDisplayPreference.energy,
            ),
          ],
        );
        await pumpScreen(tester);
        expect(find.textContaining(r'$0.00005'), findsOneWidget);
        expect(find.textContaining(r'$0.0235'), findsNothing);
      });
    });

    group('goldens: jobs list {light,dark}×{android,macos}', () {
      Future<void> pumpGolden(
        WidgetTester tester, {
        required String golden,
        required ThemeMode mode,
        required TargetPlatform platform,
      }) async {
        try {
          debugDefaultTargetPlatformOverride = platform;
          await pumpScreen(tester, mode: mode, platform: platform);
          await expectLater(
            find.byType(AiImportJobsScreen),
            matchesGoldenFile('goldens/$golden'),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }

      testWidgets('golden light android (running + dead_letter + '
          'succeeded rows)', (tester) async {
        await setupContainer(
          listResult: Right([
            _job('job-r', status: JobStatus.running),
            _job('job-d', status: JobStatus.deadLetter, lastError: 'boom'),
            _job('job-s', status: JobStatus.succeeded),
          ]),
        );
        await pumpGolden(
          tester,
          golden: 'ai_jobs_light_android.png',
          mode: ThemeMode.light,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('golden dark android', (tester) async {
        await setupContainer(
          listResult: Right([
            _job('job-r', status: JobStatus.running),
            _job('job-d', status: JobStatus.deadLetter, lastError: 'boom'),
            _job('job-s', status: JobStatus.succeeded),
          ]),
        );
        await pumpGolden(
          tester,
          golden: 'ai_jobs_dark_android.png',
          mode: ThemeMode.dark,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('golden light macos', (tester) async {
        await setupContainer(
          listResult: Right([
            _job('job-r', status: JobStatus.running),
            _job('job-d', status: JobStatus.deadLetter, lastError: 'boom'),
            _job('job-s', status: JobStatus.succeeded),
          ]),
        );
        await pumpGolden(
          tester,
          golden: 'ai_jobs_light_macos.png',
          mode: ThemeMode.light,
          platform: TargetPlatform.macOS,
        );
      });

      testWidgets('golden dark macos', (tester) async {
        await setupContainer(
          listResult: Right([
            _job('job-r', status: JobStatus.running),
            _job('job-d', status: JobStatus.deadLetter, lastError: 'boom'),
            _job('job-s', status: JobStatus.succeeded),
          ]),
        );
        await pumpGolden(
          tester,
          golden: 'ai_jobs_dark_macos.png',
          mode: ThemeMode.dark,
          platform: TargetPlatform.macOS,
        );
      });

      // The compact cost line (issue #675): known-cost rows, including the
      // unknown-status honesty copy, {light,dark}×{android,macos}.
      for (final (mode, platform, suffix) in [
        (ThemeMode.light, TargetPlatform.android, 'light_android'),
        (ThemeMode.dark, TargetPlatform.android, 'dark_android'),
        (ThemeMode.light, TargetPlatform.macOS, 'light_macos'),
        (ThemeMode.dark, TargetPlatform.macOS, 'dark_macos'),
      ]) {
        testWidgets('golden $suffix (cost rows)', (tester) async {
          await setupContainer(
            listResult: Right([
              _job('job-c', status: JobStatus.succeeded, cost: _knownCost()),
              _job('job-u', status: JobStatus.succeeded, cost: _unknownCost()),
              _job(
                'job-n',
                status: JobStatus.succeeded,
                cost: _notApplicableCost(),
              ),
            ]),
          );
          try {
            debugDefaultTargetPlatformOverride = platform;
            await pumpGolden(
              tester,
              golden: 'ai_jobs_cost_$suffix.png',
              mode: mode,
              platform: platform,
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    });
  });
}

AiImportJobCacheRow _cacheRow(String id, {String statusWire = 'pending'}) =>
    AiImportJobCacheRow(
      id: id,
      userId: 'dev-user',
      status: statusWire,
      documentKind: 'schedule',
      sourceFormat: 'csv',
      dedupKey: 'dedup-$id',
      documentDigest: 'digest-$id',
      sourceHandle: 'handle-$id',
      retries: 0,
      maxRetries: 3,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      cachedAt: DateTime.utc(2026, 1, 1),
    );
