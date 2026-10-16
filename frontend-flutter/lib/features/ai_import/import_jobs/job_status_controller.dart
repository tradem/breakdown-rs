// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../../../auth/auth_providers.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/ai_import_repository.dart'
    show AiImportRepository, isTerminalJobStatus;
import '../../../l10n/generated/app_localizations.dart';

part 'job_status_controller.g.dart';

/// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
/// #664 battery contract D5).
///
/// The ONLY SSE consumer in the app: subscribes to
/// `jobRepository.watch(jobId)` — the push-based, foreground-only event
/// stream. The subscription lives exactly as long as this provider AND the
/// app is foregrounded:
///
/// * leaving the screen disposes the provider → the subscription (and its
///   Dio cancel token) is cancelled — no stream survives the screen;
/// * the app transitioning to the background (`paused`/`hidden`/
///   `detached`) cancels the subscription immediately — zero background
///   network wake-ups;
/// * returning to the foreground (`resumed`) performs exactly ONE
///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
///   job is still non-terminal.
///
/// There is no cancel affordance (D3 — no server route): the copy says
/// processing continues; the user can only close the screen.
@Riverpod(keepAlive: false)
class AiJobStatusController extends _$AiJobStatusController {
  StreamSubscription<Result<AiImportJob>>? _sub;
  CancelToken? _cancelToken;
  late AiImportRepository _repo;
  late String _jobId;
  bool _backgrounded = false;

  @override
  AsyncValue<AiImportJob> build(String jobId) {
    final repo = ref.read(aiImportRepositoryProvider);
    _repo = repo;
    _jobId = jobId;
    _backgrounded = false;
    _subscribe();
    // App-lifecycle gate (battery contract, D5): only the foregrounded
    // screen holds an open SSE stream. The observer is removed on dispose,
    // so a disposed provider can never observe a lifecycle event.
    final lifecycle = _AppLifecycleObserver(
      onBackground: _cancelWatch,
      onResumed: _onResumed,
    );
    WidgetsBinding.instance.addObserver(lifecycle);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(lifecycle);
      // Unsubscribe stop (D5): the watch ends with the screen; no
      // background polling/stream survives disposal. The cancel token
      // aborts the in-flight HTTP stream body as well.
      unawaited(_sub?.cancel());
      _sub = null;
      _cancelToken?.cancel();
      _cancelToken = null;
    });
    return const AsyncValue<AiImportJob>.loading();
  }

  void _subscribe() {
    unawaited(_sub?.cancel());
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    // onError maps stream faults (a deserialization failure or an
    // exception escaping the Result mapping inside the async* watch
    // generator) into the state — without it the error goes to the zone
    // unhandled and the screen spins forever with no re-arm affordance.
    _sub = _repo
        .watch(_jobId, cancelToken: token)
        .listen(
          (event) {
            if (!ref.mounted) return;
            state = event.match(
              (err) => AsyncValue<AiImportJob>.error(err, StackTrace.current),
              (job) => AsyncValue<AiImportJob>.data(job),
            );
          },
          onError: (Object err, StackTrace stack) {
            if (!ref.mounted) return;
            state = AsyncValue<AiImportJob>.error(err, stack);
          },
        );
  }

  /// Battery contract (D5): the app left the foreground — cancel the SSE
  /// subscription AND the underlying HTTP stream immediately, so zero
  /// background network wake-ups occur.
  void _cancelWatch() {
    _backgrounded = true;
    unawaited(_sub?.cancel());
    _sub = null;
    // Closing the stream subscription alone does not abort the in-flight
    // request body — the cancel token does (D5).
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// Battery contract (D5): back in the foreground — exactly ONE snapshot
  /// GET, and a fresh SSE subscription unless the job is terminal or the
  /// app backgrounded again while the GET was in flight.
  Future<void> _onResumed() async {
    if (!_backgrounded || !ref.mounted) return;
    _backgrounded = false;
    final snapshot = await _repo.getJobAndCache(_jobId);
    // A backgrounding DURING the in-flight snapshot must not reopen the
    // watch (battery contract): re-check the lifecycle state after the
    // await — the snapshot itself may still complete, but no subscription
    // is armed while the app is backgrounded.
    if (_backgrounded || !ref.mounted) return;
    state = snapshot.match(
      (err) => AsyncValue<AiImportJob>.error(err, StackTrace.current),
      (job) => AsyncValue<AiImportJob>.data(job),
    );
    final job = snapshot.getRight().toNullable();
    if (job != null && isTerminalJobStatus(job.status)) return;
    // A FAILED snapshot must not leave the watch cancelled: the error
    // stays visible in the state, and the re-subscribed SSE stream is
    // itself the recovery path — its first frame is a fresh snapshot.
    _subscribe();
  }

  /// Re-arms the watch after exhaustion or a manual leave (the
  /// `ai_import.watch_exhausted` retry affordance — never a fabricated
  /// terminal state).
  Future<void> rearm() async {
    ref.invalidateSelf();
  }
}

/// Bridges [WidgetsBindingObserver] app-lifecycle transitions to the
/// controller's battery-contract callbacks. A separate class (not a mixin
/// on the notifier) keeps Riverpod's generated notifier free of widget-
/// binding machinery and makes the transitions unit-testable.
class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver({required this.onBackground, required this.onResumed});

  final void Function() onBackground;
  final void Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        onBackground();
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.inactive:
        // Transient (in-app dialogs, permission sheets) — neither cancel
        // nor refresh; the SSE stream stays alive while inactive.
        break;
    }
  }
}

/// The persisted apply context of a cached job row (design §2.3): the
/// apply navigation reads the episode/series from HERE, never from the
/// navigation stack. `null` context → the apply screen requires the
/// explicit episode picker.
@riverpod
Future<AiJobContext?> aiJobContext(Ref ref, String jobId) async {
  final repo = ref.read(aiImportRepositoryProvider);
  // Identity-scoped cache read: the context rows belong to the signed-in
  // sub — a same-id row of a previous identity is never readable here.
  String sub;
  try {
    final session = await ref.read(authSessionControllerProvider.future);
    sub = session?.sub ?? '';
  } on Object {
    return null;
  }
  final rows = await repo.readCached(sub);
  final err = rows.getLeft().toNullable();
  if (err != null) return null;
  for (final row in rows.getRight().toNullable()!) {
    if (row.id == jobId) {
      final episodeId = row.episodeId;
      if (episodeId == null) return null;
      return AiJobContext(episodeId: episodeId, projectId: row.projectId ?? '');
    }
  }
  return null;
}

/// The persisted apply context (episode + series) of a job.
class AiJobContext {
  const AiJobContext({required this.episodeId, required this.projectId});

  final String episodeId;
  final String projectId;
}

/// Localized copy for the job-status error banner (watch failures,
/// exhaustion) keyed on the stable problem `code`. `ai-import.forbidden` is
/// the scoped wire code the backend emits for ALL AI-import job denials
/// (ownership, season-scope, cross-resource) — the copy is access-neutral
/// (CodeRabbit #480). The not-found arm keys on `ai-import.not-found`, the
/// scoped wire code the backend emits for a missing/oracle-hidden job (issue
/// #481) — the client never fabricates a job not-found code of its own.
String jobWatchErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'ai-import.forbidden' => l10n.jobWatchForbidden,
      'ai_import.watch_exhausted' => l10n.jobWatchExhausted,
      'ai-import.not-found' => l10n.jobWatchNotFound,
      _ when error.code.startsWith('transport.') => l10n.jobWatchNetwork,
      _ => l10n.jobWatchGeneric(error.code),
    };
