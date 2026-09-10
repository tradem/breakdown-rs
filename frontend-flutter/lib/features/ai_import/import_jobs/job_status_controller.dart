// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';

import '../../../auth/auth_providers.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';

part 'job_status_controller.g.dart';

/// The job-status controller (`flutter-ai-import-workflow` task 3.2).
///
/// Subscribes to `jobRepository.watch(jobId)` — the bounded,
/// foreground-only backoff watch (D5). The subscription lives exactly as
/// long as this provider: leaving the screen disposes the provider, which
/// cancels the subscription and STOPS the watch (unsubscribe stop);
/// re-entering re-arms it. Terminal statuses end the stream by
/// themselves. There is no cancel affordance (D3 — no server route): the
/// copy says processing continues; the user can only close the screen.
@Riverpod(keepAlive: false)
class AiJobStatusController extends _$AiJobStatusController {
  StreamSubscription<Result<AiImportJob>>? _sub;

  @override
  AsyncValue<AiImportJob> build(String jobId) {
    final repo = ref.read(aiImportRepositoryProvider);
    // Re-arm on every (re)build; the previous subscription (if any) is
    // cancelled by Riverpod's dispose of the old notifier instance.
    // onError maps stream faults (a deserialization failure or an
    // exception escaping the Result mapping inside the async* watch
    // generator) into the state — without it the error goes to the zone
    // unhandled and the screen spins forever with no re-arm affordance.
    _sub = repo
        .watch(jobId)
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
    ref.onDispose(() {
      // Unsubscribe stop (D5): the watch ends with the screen; no
      // background polling survives disposal.
      unawaited(_sub?.cancel());
      _sub = null;
    });
    return const AsyncValue<AiImportJob>.loading();
  }

  /// Re-arms the watch after exhaustion or a manual leave (the
  /// `ai_import.watch_exhausted` retry affordance — never a fabricated
  /// terminal state).
  Future<void> rearm() async {
    ref.invalidateSelf();
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
      return AiJobContext(episodeId: episodeId, seriesId: row.seriesId ?? '');
    }
  }
  return null;
}

/// The persisted apply context (episode + series) of a job.
class AiJobContext {
  const AiJobContext({required this.episodeId, required this.seriesId});

  final String episodeId;
  final String seriesId;
}

/// Localized copy for the job-status error banner (watch failures,
/// exhaustion) keyed on the stable problem `code`.
String jobWatchErrorCopy(ProblemError error) => switch (error.code) {
  'ai_import.watch_exhausted' =>
    'Still no update from the backend — the job keeps processing. '
        'Re-arm the watch or come back later.',
  'ai_import.not_found' =>
    'This job does not exist (or belongs to another account).',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the status could not be refreshed.',
  _ => 'The status could not be refreshed (${error.code}).',
};
