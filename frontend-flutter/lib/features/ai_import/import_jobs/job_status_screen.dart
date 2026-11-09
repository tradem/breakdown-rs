// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../data/cache/relative_time.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/locale_formatters.dart';
import '../clippy/clippy_trigger.dart';
import '../clippy/karl_kleiderbuegel_overlay.dart';
import 'import_state.dart';
import 'job_cost_card.dart';
import 'job_eta.dart';
import 'job_status_controller.dart';
import 'preview_screen.dart';
import '../../../design/material_icons.dart';
import '../../../design/components/breakdown_app_bar.dart';

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
      appBar: BreakdownAppBar(title: l10nOf(context).aiJobTitle),
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
              // Issue #771: the job repeats the target the submit screen
              // showed, so an import is attributable AFTER the fact instead of
              // only being believed.
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _JobCard(job: value),
                  const SizedBox(height: 12),
                  _JobTargetCard(job: value),
                ],
              ),
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

/// The job's recorded import TARGET (issue #771).
///
/// `AiImportJob.target` carries the season id + both production-global numbers
/// as the server snapshotted them at dispatch. The card therefore needs no
/// second read — and a job uploaded before the field existed renders the honest
/// "not recorded" narrative instead of a guessed season.
class _JobTargetCard extends StatelessWidget {
  const _JobTargetCard({required this.job});

  final AiImportJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    final target = job.target;
    return Card(
      key: const Key('ai-job-target'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiImportTargetTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              target == null
                  ? l10n.aiImportTargetNotRecorded
                  : l10n.aiImportTargetLine(
                      l10n.blockSeasonNumber('${target.seasonNumber}'),
                      // Issue #829 (review of PR #856): a block-less upload
                      // carries its season with `block_number: null` until the
                      // target is attached, so the card must say "unknown"
                      // instead of interpolating the word "null" into the line.
                      target.blockNumber == null
                          ? l10n.aiImportTargetUnknownBlock
                          : l10n.blockTileLabel('${target.blockNumber}'),
                    ),
              key: const Key('ai-job-target-line'),
            ),
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
    // Issue #822: one derivation, rendered by both the retryable and the
    // terminal card (and, compactly, by the jobs row).
    final degradation = aiProviderDegradation(job);

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
              // Issue #822: an aggregated provider outage is its own state on
              // the terminal card too — with the spent-budget copy, because
              // this card can no longer keep a retry promise.
              if (degradation != null) ...[
                const SizedBox(height: 12),
                _ProviderDegradedBanner(
                  degradation: degradation,
                  onErrorContainer: true,
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
                        aiJobFailureReason(
                          l10nOf(context),
                          attempt.code,
                          // Issue #822: a terminal card never renders the
                          // "the next attempt may succeed" promise.
                          retryPossible: false,
                        ),
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
      // Issue #827: the block the SCRIPT states, published from the first
      // progress frame. `null` means the document names none — the card then
      // renders nothing here and the preview screen shows the import target as
      // the associated block instead of an invented number.
      final blockNumber = progress?.blockNumber;
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
              // Issue #762: the coarse remaining-time estimate. Only a
              // RUNNING job has a time anchor — `pending` means queued, and
              // its wait is not extraction time. The widget renders nothing
              // (and occupies no space) when it has nothing to say.
              if (job.status == JobStatus.running) _JobExtractionEta(job: job),
              // Issue #827: the block the script states, with the same visual
              // weight as the episode chips below it.
              if (blockNumber != null) ...[
                const SizedBox(height: 8),
                Text(
                  key: const Key('ai-job-block-label'),
                  l10nOf(context).aiJobBlockSeenLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  key: const Key('ai-job-block-chips'),
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Chip(
                      key: const Key('ai-job-block-chip'),
                      label: Text(
                        l10nOf(context).blockTileLabel('$blockNumber'),
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
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
              if (degradation != null) ...[
                const SizedBox(height: 8),
                _ProviderDegradedBanner(degradation: degradation),
              ],
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
            // The immutable per-import cost snapshot (issue #675). The
            // terminal `succeeded` SSE frame carries `job.cost` (#664),
            // so this card appears with the completion push — no extra
            // refresh.
            AiJobCostCard(job: job),
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
/// One window label per failure boundary (issue #822).
///
/// A provider outage is usually measured in minutes, so the time of day is the
/// useful value — but a run can straddle days, and a bare clock would then read
/// as an impossible window. The date is therefore added only when the two
/// boundaries are not on the same calendar day.
String _degradationBoundaryLabel(
  BuildContext context,
  DateTime value,
  DateTime? peer,
) {
  final clock = formatClock(context, value);
  if (peer == null) return clock;
  final sameDay =
      value.toLocal().year == peer.toLocal().year &&
      value.toLocal().month == peer.toLocal().month &&
      value.toLocal().day == peer.toLocal().day;
  if (sameDay) return clock;
  return '${formatMediumDate(context, value.toLocal())} $clock';
}

/// The aggregated "AI provider degraded" state (issue #822).
///
/// Renders ONE conclusion for a contiguous run of provider-attributed attempts
/// — how many failed and over which window — instead of leaving the reviewer to
/// count identical history rows. The copy names the dependency (the AI
/// provider), never "a service": the attribution comes from the stable attempt
/// `code`, never from the free-form `error_summary` (AGENTS.md §5).
///
/// The next attempt time is NOT duplicated here: the retryable card renders the
/// live "next retry in …" affordance (`_NextRetryEta`) directly below, so the
/// card as a whole carries count, window and next attempt without two
/// countdowns disagreeing. A terminal card spends no countdown at all and says
/// the budget is spent instead.
class _ProviderDegradedBanner extends StatelessWidget {
  const _ProviderDegradedBanner({
    required this.degradation,
    this.onErrorContainer = false,
  });

  final AiProviderDegradation degradation;

  /// The terminal card's palette (`errorContainer`); the retryable card keeps
  /// the default surface colours with a tonal container.
  final bool onErrorContainer;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final scheme = Theme.of(context).colorScheme;
    final foreground = onErrorContainer
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;
    final first = _degradationBoundaryLabel(
      context,
      degradation.firstFailureAt,
      degradation.lastFailureAt,
    );
    final last = _degradationBoundaryLabel(
      context,
      degradation.lastFailureAt,
      degradation.firstFailureAt,
    );
    final count = '${degradation.failedAttempts}';
    // The exhaustion claim is rendered ONLY where it is provable (a
    // `dead_letter` whose newest attempt carries the retryable provider code —
    // see `AiProviderDegradation.retryBudgetSpent`). The per-attempt history
    // rows below the banner use the terminal reason variants, which promise no
    // retry and claim no exhaustion, because `dead_letter` also happens on a
    // non-retryable failure and `payload_unavailable` is terminal for a
    // different reason entirely.
    final body = degradation.retryBudgetSpent
        ? l10n.aiJobProviderDegradedBudgetSpent(count, first, last)
        : l10n.aiJobProviderDegradedBody(count, first, last);
    return Container(
      key: const Key('ai-job-provider-degraded'),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: onErrorContainer
            ? scheme.onErrorContainer.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: onErrorContainer
              ? scheme.onErrorContainer.withValues(alpha: 0.24)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                BreakdownMaterialIcons.aiJobProviderDegraded,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.aiJobProviderDegradedTitle,
                  key: const Key('ai-job-provider-degraded-title'),
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            key: const Key('ai-job-provider-degraded-body'),
            style: TextStyle(color: foreground, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

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

/// Live, coarse remaining-time estimate of the extraction phase
/// (issue #762).
///
/// The math is the pure [estimateAiJobEta]; this widget only owns the two
/// things a pure function cannot: the previous frame's estimate (the EMA
/// carrier) and a bounded local ticker. The ticker rebuilds *this* widget
/// only — it never touches the network, so the "no polling" decision of
/// #664/#547 stands, and the SSE remains the only source of job state.
///
/// A ticker rebuild deliberately does NOT re-run the EMA: the counters did not
/// change, so re-deriving a per-unit cost from a growing elapsed time would
/// make the countdown climb. The EMA advances only when the backend publishes
/// new counters; the ticker only re-evaluates the stall window.
class _JobExtractionEta extends ConsumerStatefulWidget {
  const _JobExtractionEta({required this.job});

  final AiImportJob job;

  @override
  ConsumerState<_JobExtractionEta> createState() => _JobExtractionEtaState();
}

class _JobExtractionEtaState extends ConsumerState<_JobExtractionEta> {
  /// Coarse refresh of the stall window; no network involved.
  static const Duration _tick = Duration(seconds: 30);

  Timer? _timer;

  /// The counter pair the current [AiJobEta] was derived from — the guard that
  /// keeps the EMA from re-running on a ticker rebuild.
  AiJobProgressUnits? _units;

  /// The attempt (`AiImportProgress.startedAt`) [_eta] belongs to.
  ///
  /// A silent SSE reconnect can deliver the first snapshot of a NEW attempt
  /// (a retry the worker re-claimed): its counters happen to differ, so the
  /// counter guard alone would smooth the new attempt's rate against the
  /// previous attempt's estimate. The backend's claim clears its progress for
  /// exactly that reason; the client must drop its smoothing state with it.
  DateTime? _attemptStartedAt;

  /// The smoothed estimate of the last counter frame (EMA carrier).
  AiJobEta? _eta;

  @override
  void initState() {
    super.initState();
    _captureEstimate();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _JobExtractionEta oldWidget) {
    super.didUpdateWidget(oldWidget);
    final progress = widget.job.progress;
    final nextUnits = aiJobProgressUnits(progress);
    if (nextUnits != _units || progress?.startedAt != _attemptStartedAt) {
      // New counters or a new attempt (a live SSE frame) — advance the EMA
      // against the last estimate of THIS attempt, so one slow chunk cannot
      // make the countdown jump and a retry does not inherit the old rate.
      _captureEstimate();
    }
    _syncTimer();
  }

  void _captureEstimate() {
    final progress = widget.job.progress;
    final startedAt = progress?.startedAt;
    if (startedAt != _attemptStartedAt) {
      // A different attempt: its cadence says nothing about this one.
      _eta = null;
      _attemptStartedAt = startedAt;
    }
    _units = aiJobProgressUnits(progress);
    _eta = estimateAiJobEta(
      progress: progress,
      // The frame's OWN write stamp, not the screen clock: the measured
      // interval must be extraction time. A client-side `now` would count every
      // second the screen was closed, backgrounded or offline as work — the
      // cost, the estimate and the stall window would all grow with the time
      // the screen stayed away. A pre-#762 frame carries no stamp; the clock is
      // then the only option left.
      now: progress?.writtenAt ?? ref.read(clockProvider).now(),
      previous: _eta,
    );
  }

  /// The freshest progress-frame stamp, or the job's write time when a frame
  /// carries none (pre-#762 backend). Never `updated_at` while a stamp exists:
  /// heartbeats refresh that continuously, so it would mask a real stall.
  DateTime get _lastFrameAt =>
      widget.job.progress?.writtenAt ?? widget.job.updatedAt;

  void _syncTimer() {
    final needsTimer = _units != null;
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
    // No counters (a pre-#762 frame, a schedule job's single unit) → nothing
    // to estimate. Rendering "estimating …" forever would be noise, not
    // honesty.
    if (_units == null) return const SizedBox.shrink();
    final l10n = l10nOf(context);
    final now = ref.watch(clockProvider).now();
    final eta = _eta;
    final stalled =
        eta != null &&
        aiJobEtaStalled(eta: eta, lastFrameAt: _lastFrameAt, now: now);
    return Padding(
      // The spacing lives HERE so an absent estimate takes no layout space: a
      // job without counters must render byte-identically to pre-#762.
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        aiJobEtaText(
          eta: eta,
          stalled: stalled,
          copy: AiJobEtaCopy(
            calculating: l10n.aiJobEtaCalculating,
            delayed: l10n.aiJobEtaDelayed,
            imminent: l10n.aiJobEtaImminent,
            minutes: (count) => l10n.aiJobEtaMinutes(count),
            hours: (count) => l10n.aiJobEtaHours(count),
            rangeMinutes: (lower, upper) =>
                l10n.aiJobEtaRangeMinutes(lower, upper),
            rangeHours: (lower, upper) => l10n.aiJobEtaRangeHours(lower, upper),
          ),
        ),
        key: const Key('ai-job-eta'),
        style: Theme.of(context).textTheme.bodySmall,
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
