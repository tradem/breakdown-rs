// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../data/cache/relative_time.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../clippy/clippy_trigger.dart';
import '../clippy/karl_kleiderbuegel_overlay.dart';
import 'import_state.dart';
import 'job_status_controller.dart';
import 'preview_screen.dart';

/// The job-status screen (`flutter-ai-import-workflow` task 3.2).
///
/// Renders the full status matrix honestly:
/// * pending/running — indeterminate progress (no fabricated percentage);
/// * failed (retryable) — "retry scheduled" with `retries/max_retries`;
/// * dead_letter / payload_unavailable — terminal error cards, primary
///   copy keyed on the status, `last_error` as SECONDARY detail only;
/// * succeeded — the path to the preview screen.
///
/// There is NO cancel affordance (D3 — no server route exists): the copy
/// says processing continues and the screen can be closed. Leaving the
/// screen disposes the watch (unsubscribe stop); re-entering re-arms it.
class AiJobStatusScreen extends ConsumerWidget {
  const AiJobStatusScreen({
    required this.jobId,
    this.duplicate = false,
    super.key,
  });

  final String jobId;

  /// True when the upload 200'd (digest-duplicate): the explicit
  /// "already imported (duplicate)" callout renders above the status —
  /// nothing implies a second import was created.
  final bool duplicate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(aiJobStatusControllerProvider(jobId));

    // Karl Kleiderbügel flow state (issue #516): derived ONLY from this
    // screen's own watched status — running/droop/proud reactions.
    final clippyState = switch (status) {
      AsyncData(:final value) => switch (value.status) {
        JobStatus.pending => ClippyFlowState.queued,
        JobStatus.running => ClippyFlowState.running,
        JobStatus.failed => ClippyFlowState.error,
        JobStatus.succeeded => ClippyFlowState.success,
        _ => ClippyFlowState.idle,
      },
      AsyncError() => ClippyFlowState.error,
      _ => ClippyFlowState.idle,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).aiJobTitle)),
      body: KarlKleiderbuegelOverlay(
        flowState: clippyState,
        child: ListView(
          key: const Key('ai-job-status-screen'),
          padding: const EdgeInsets.all(16),
          children: [
            if (duplicate)
              Card(
                key: const Key('ai-job-duplicate-callout'),
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10nOf(context).aiJobDuplicate),
                ),
              ),
            switch (status) {
              AsyncData(:final value) => _JobCard(job: value),
              AsyncError(:final error) => _WatchErrorCard(
                jobId: jobId,
                error: error is ProblemError
                    ? error
                    : ProblemError(code: 'unknown', detail: '$error'),
              ),
              _ => const SizedBox(
                key: Key('ai-job-status-loading'),
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              ),
            },
            const SizedBox(height: 16),
            const _NoCancelNotice(),
          ],
        ),
      ),
    );
  }
}

/// The per-status card (the status matrix, task 3.2).
class _JobCard extends ConsumerWidget {
  const _JobCard({required this.job});

  final AiImportJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lastError = job.lastError;
    final attempts = job.attempts;

    if (jobStatusTerminalError(job.status)) {
      return Card(
        key: const Key('ai-job-terminal-error'),
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      jobStatusCopy(l10nOf(context), job.status),
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (lastError != null && lastError.isNotEmpty) ...[
                const SizedBox(height: 8),
                // `last_error` is SECONDARY detail only — never the
                // primary copy, never user-facing error identity.
                Text(
                  lastError,
                  key: const Key('ai-job-last-error'),
                  style: TextStyle(
                    color: scheme.onErrorContainer.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
              // The per-attempt history (issue #637) survives the
              // `last_error` overwrite; each row's reason is keyed on its
              // stable problem `code` (issue #639), never the raw summary.
              if (attempts != null && attempts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10nOf(context).aiJobAttemptHistoryLabel,
                  key: const Key('ai-job-attempt-history'),
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                for (final attempt in attempts)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      key: Key('ai-job-attempt-${attempt.attemptNo}'),
                      l10nOf(context).aiJobAttemptRow(
                        '${attempt.attemptNo}',
                        aiJobFailureReason(l10nOf(context), attempt.code),
                      ),
                      style: TextStyle(
                        color: scheme.onErrorContainer.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    if (jobStatusInProgress(job.status)) {
      final progress = job.progress;
      final chunksTotal = progress?.chunksTotal;
      final chunk = progress?.chunk;
      final episodes = progress?.episodesSeen;
      // Determinate progress ONLY when the backend carries a positive
      // total — never a fabricated percentage (spec: indeterminate
      // affordance otherwise).
      final determinate = chunksTotal != null && chunksTotal > 0;
      return Card(
        key: const Key('ai-job-in-progress'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    key: const Key('ai-job-indeterminate'),
                    width: 24,
                    height: 24,
                    child: determinate
                        ? null
                        : const CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      // The localized stage when the job publishes one;
                      // the plain status copy otherwise.
                      key: const Key('ai-job-stage'),
                      progress == null
                          ? jobStatusCopy(l10nOf(context), job.status)
                          : aiJobStageCopy(l10nOf(context), progress.stage),
                    ),
                  ),
                ],
              ),
              if (determinate) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  key: const Key('ai-job-chunk-progress'),
                  value: (chunk ?? 0) / chunksTotal,
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Text(
                  key: const Key('ai-job-chunk-counter'),
                  l10nOf(context)
                      .aiJobChunkProgress('${chunk ?? 0}', '$chunksTotal'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (episodes != null && episodes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  key: const Key('ai-job-episodes-label'),
                  l10nOf(context).aiJobEpisodesSeenLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  key: const Key('ai-job-episodes-chips'),
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final label in episodes)
                      Chip(
                        key: Key(
                          'ai-job-episode-'
                          '${label.replaceAll(' ', '-')}',
                        ),
                        label: Text(label),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (job.status == JobStatus.failed) {
      // Retryable: a live "next retry in …" ETA (when the backend carries
      // one), the code-keyed reason of the newest attempt, and the visible
      // retry budget. The raw `error_summary` never renders here — only the
      // localized, code-keyed narrative (AGENTS.md §5).
      final newestAttempt = attempts != null && attempts.isNotEmpty
          ? attempts.first
          : null;
      return Card(
        key: const Key('ai-job-retryable'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(jobStatusCopy(l10nOf(context), job.status)),
              const SizedBox(height: 4),
              Text(
                key: const Key('ai-job-retry-budget'),
                l10nOf(context).aiJobRetryBudget(
                  '${job.maxRetries + 1}',
                  '${job.retries + 1}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _NextRetryEta(nextAttemptAt: job.nextAttemptAt),
              if (newestAttempt != null) ...[
                const SizedBox(height: 8),
                Text(
                  key: const Key('ai-job-failure-reason'),
                  aiJobFailureReason(l10nOf(context), newestAttempt.code),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // succeeded → the preview path.
    return Card(
      key: const Key('ai-job-succeeded'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(jobStatusCopy(l10nOf(context), job.status)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('ai-job-open-preview'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AiPreviewScreen(jobId: job.id),
                ),
              ),
              child: Text(l10nOf(context).aiJobReviewPreview),
            ),
          ],
        ),
      ),
    );
  }
}

/// Watch failure card (transport/exhaustion) with the re-arm affordance.
class _WatchErrorCard extends ConsumerWidget {
  const _WatchErrorCard({required this.jobId, required this.error});

  final String jobId;
  final ProblemError error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(aiJobStatusControllerProvider(jobId).notifier);
    return Card(
      key: const Key('ai-job-watch-error'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              jobWatchErrorCopy(l10nOf(context), error),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('ai-job-rearm'),
              onPressed: controller.rearm,
              child: Text(l10nOf(context).aiJobCheckAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live "next retry in …" ETA (issue #639).
///
/// Recomputes on a bounded ticker so the countdown stays honest without a
/// per-second rebuild. The copy is coarse-bucketed (see [relativeTimeUntil]);
/// an absent [nextAttemptAt] degrades to a localized "retry scheduled — time
/// unknown", never a fabricated countdown. The clock is the injectable
/// [clockProvider], so widget tests and goldens stay deterministic.
class _NextRetryEta extends ConsumerStatefulWidget {
  const _NextRetryEta({required this.nextAttemptAt});

  final DateTime? nextAttemptAt;

  @override
  ConsumerState<_NextRetryEta> createState() => _NextRetryEtaState();
}

class _NextRetryEtaState extends ConsumerState<_NextRetryEta> {
  /// Coarse bucket size: `relativeTimeUntil` changes at most once per minute,
  /// so a 30 s tick keeps the copy current without a per-frame rebuild.
  static const Duration _tick = Duration(seconds: 30);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _NextRetryEta oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    final needsTimer = widget.nextAttemptAt != null;
    if (needsTimer && _timer == null) {
      _timer = Timer.periodic(_tick, (_) {
        if (mounted) setState(() {});
      });
    } else if (!needsTimer && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final due = widget.nextAttemptAt;
    final text = due == null
        ? l10n.aiJobNextRetryUnknown
        : relativeTimeUntil(
            due,
            clock: ref.watch(clockProvider),
            // The data-layer formatter stays string-free; the units come from
            // the resolved catalog (ADR-034).
            copy: RelativeTimeUntilCopy(
              imminent: l10n.aiJobNextRetryImminent,
              minutes: (count) => l10n.aiJobNextRetryMinutes('$count'),
              hours: (count) => l10n.aiJobNextRetryHours('$count'),
              days: (count) => l10n.aiJobNextRetryDays('$count'),
            ),
          );
    return Text(
      text,
      key: const Key('ai-job-next-retry'),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

/// The honest "no cancel route" notice (D3): processing continues
/// server-side; the user can only close the screen.
class _NoCancelNotice extends StatelessWidget {
  const _NoCancelNotice();

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('ai-job-no-cancel'),
    children: [
      Icon(Icons.info_outline, size: 16, color: Theme.of(context).hintColor),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Processing continues on the server — there is no cancel. You '
          'can close this screen and come back later.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
