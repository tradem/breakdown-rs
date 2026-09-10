// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('AI import job')),
      body: ListView(
        key: const Key('ai-job-status-screen'),
        padding: const EdgeInsets.all(16),
        children: [
          if (duplicate)
            Card(
              key: const Key('ai-job-duplicate-callout'),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Already imported (duplicate) — showing the existing '
                  'job. No second import was created.',
                ),
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
                      jobStatusCopy(job.status),
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
            ],
          ),
        ),
      );
    }

    if (jobStatusInProgress(job.status)) {
      return Card(
        key: const Key('ai-job-in-progress'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SizedBox(
                key: Key('ai-job-indeterminate'),
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(jobStatusCopy(job.status))),
            ],
          ),
        ),
      );
    }

    if (job.status == JobStatus.failed) {
      // Retryable: "retry scheduled" with the visible retry budget.
      return Card(
        key: const Key('ai-job-retryable'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(jobStatusCopy(job.status)),
              const SizedBox(height: 4),
              Text(
                key: const Key('ai-job-retry-budget'),
                'Retry ${job.retries + 1} of ${job.maxRetries + 1}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                Expanded(child: Text(jobStatusCopy(job.status))),
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
              child: const Text('Review preview'),
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
              jobWatchErrorCopy(error),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('ai-job-rearm'),
              onPressed: controller.rearm,
              child: const Text('Check again'),
            ),
          ],
        ),
      ),
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
