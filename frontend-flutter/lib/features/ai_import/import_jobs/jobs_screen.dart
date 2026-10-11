// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/spacing.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../clippy/clippy_trigger.dart';
import '../clippy/karl_klammer_overlay.dart';
import '../../../l10n/locale_formatters.dart';
import 'import_submit_screen.dart' show AiImportSubmitScreen;
import 'job_status_screen.dart';
import 'jobs_controller.dart';

/// The AI-import **jobs screen** (issue #547): the "what did I import"
/// surface over the previously-unused `GET /v1/ai-import/jobs` wiring.
///
/// Renders cached status newest-first and arms **no** watch (D5 — the
/// single foreground job watch stays owned by `AiJobStatusScreen`, which
/// is what a row tap pushes). Pull-to-refresh re-runs exactly the list
/// route — the status authority for rows; there is no per-row polling
/// and no fabricated progress indicator (the wire carries
/// `retries`/`max_retries`, never a percentage).
///
/// // AUTHZ-GATE: the list route is ownership-scoped server-side; the
/// client gate runs in `aiImportJobsFetch` (session resolved BEFORE the
/// call — no session, no request) and denials route through the
/// code-keyed copy (`aiJobsListErrorCopy`), never the server `detail`.
/// The sibling AI-import entry in the production overview keeps its
/// block-scope gate (`import_submit_controller.dart`); this entry does
/// not weaken it — the list itself issues no block-scoped write.
class AiImportJobsScreen extends ConsumerWidget {
  const AiImportJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final state = ref.watch(aiImportJobsView);
    final loading =
        ref.watch(aiImportJobsViewControllerProvider).isLoading &&
        state.rows.isEmpty;

    // Karl Klammer flow state (issue #516): derived ONLY from this
    // screen's own watched state — never from a second projection call.
    final clippyState = state.error != null && state.rows.isEmpty
        ? ClippyFlowState.error
        : state.rows.any(
            (r) =>
                r.status == JobStatus.pending || r.status == JobStatus.running,
          )
        ? ClippyFlowState.running
        : ClippyFlowState.idle;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiJobsTitle)),
      body: KarlKlammerOverlay(
        flowState: clippyState,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(aiImportJobsViewControllerProvider.notifier).refresh(),
          child: Builder(
            builder: (context) {
              if (loading) return const _JobsSkeleton();
              if (state.error != null && state.rows.isEmpty) {
                return _JobsError(state: state);
              }
              if (state.rows.isEmpty) return const _JobsEmpty();
              return _JobsList(state: state);
            },
          ),
        ),
      ),
    );
  }
}

/// Cached-first paint: the seeded rows render immediately, so a cold
/// start never blanks behind the fetch; `isStale` marks a failed refetch
/// serving retained rows (banner keyed on the shared stale copy — the
/// cache is a local optimization, AGENTS.md §8).
class _JobsList extends ConsumerWidget {
  const _JobsList({required this.state});

  final AiImportJobsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return ListView(
      key: const Key('ai-jobs-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
      children: [
        if (state.isStale)
          Card(
            key: const Key('ai-jobs-stale-banner'),
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16,
              vertical: AppSpacing.space4,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space12),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 16,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Expanded(child: Text(l10n.seasonsStaleBanner)),
                ],
              ),
            ),
          )
        else if (state.error != null)
          Card(
            key: const Key('ai-jobs-error-banner'),
            color: Theme.of(context).colorScheme.errorContainer,
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16,
              vertical: AppSpacing.space4,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space12),
              child: Text(
                aiJobsListErrorCopy(l10n, state.error!),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        for (final job in state.rows) _JobRow(job: job),
      ],
    );
  }
}

/// One jobs-list row. The row is a navigation target, never a dispatch
/// surface: tap pushes `AiJobStatusScreen(jobId)`, which owns the single
/// foreground watch and its re-arm / preview affordances. The status
/// icon reinforces the always-visible status text (glossary rule —
/// icons are never the sole carrier of meaning); terminal failures are
/// additionally error-colored so `dead_letter`/`payload_unavailable`
/// are visibly distinct at a glance.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final AiImportJobRowView job;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final scheme = Theme.of(context).colorScheme;
    final kind = switch (job.documentKind) {
      DocumentKind.schedule => l10n.aiImportSchedule,
      DocumentKind.script => l10n.aiImportScript,
      // An unknown future kind degrades honestly — never a guessed label.
      _ => l10n.commonUnknown,
    };
    final statusColor = job.isTerminalFailure || job.hasLastError
        ? scheme.error
        : scheme.primary;

    return ListTile(
      key: Key('ai-jobs-row-${job.id}'),
      leading: Icon(jobStatusIcon(job.status), color: statusColor),
      title: Text(
        // gen-l10n orders parameters alphabetically: (date, kind) — the
        // template renders "kind · date" (screen spec order).
        l10n.aiJobsRowSubtitle(formatMediumDate(context, job.createdAt), kind),
        key: Key('ai-jobs-row-title-${job.id}'),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.statusLabel(l10n), key: Key('ai-jobs-row-status-${job.id}')),
          if (job.status == JobStatus.failed)
            Text(
              l10n.aiJobRetryBudget(
                '${job.maxRetries + 1}',
                '${job.retries + 1}',
              ),
              key: Key('ai-jobs-row-retry-budget-${job.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      trailing: job.hasLastError
          ? Icon(Icons.error_outline, color: scheme.error)
          : const Icon(Icons.chevron_right),
      onTap: () {
        // Fire-and-forget navigation (no result consumed). The pushed
        // status screen arms the single watch; leaving it disposes it.
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AiJobStatusScreen(jobId: job.id),
            ),
          ),
        );
      },
    );
  }
}

/// Status icon per [JobStatus] (pure, widget-tier tested). Passive
/// status glyphs — never the sole carrier of meaning (the row always
/// renders the localized status text next to them). `null` (an unknown
/// future wire status) gets the honest help glyph.
IconData jobStatusIcon(JobStatus? status) => switch (status) {
  JobStatus.pending => Icons.hourglass_top,
  JobStatus.running => Icons.autorenew,
  JobStatus.succeeded => Icons.check_circle_outline,
  JobStatus.failed => Icons.error_outline,
  JobStatus.deadLetter => Icons.block,
  JobStatus.payloadUnavailable => Icons.cloud_off,
  // An unknown future status (or a strict-parse failure) — the honest
  // help glyph; the row's status TEXT always renders beside it.
  _ => Icons.help_outline,
};

/// Honest empty state: "no import yet" — with the CTA to the import
/// entry (the submit screen), never a fabricated list.
class _JobsEmpty extends StatelessWidget {
  const _JobsEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return ListView(
      key: const Key('ai-jobs-empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        Icon(
          Icons.history,
          size: 48,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: AppSpacing.space16),
        Center(
          child: Text(
            l10n.aiJobsEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.space16),
        Center(
          child: FilledButton(
            key: const Key('ai-jobs-empty-cta'),
            onPressed: () {
              // Fire-and-forget navigation (no result consumed).
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiImportSubmitScreen(),
                  ),
                ),
              );
            },
            child: Text(l10n.aiJobsEmptyCta),
          ),
        ),
      ],
    );
  }
}

/// List-fetch failure with NO retained rows: the honest full error
/// state, copy keyed on the stable `code`, retry re-runs exactly the
/// list route (no watch arming, D5).
class _JobsError extends ConsumerWidget {
  const _JobsError({required this.state});

  final AiImportJobsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return ListView(
      key: const Key('ai-jobs-error'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space12),
            child: Column(
              children: [
                Text(
                  aiJobsListErrorCopy(l10n, state.error!),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.space12),
                OutlinedButton(
                  key: const Key('ai-jobs-error-retry'),
                  onPressed: () => ref
                      .read(aiImportJobsViewControllerProvider.notifier)
                      .refresh(),
                  child: Text(l10n.aiJobCheckAgain),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Loading skeleton: three placeholder rows — the cached-first paint
/// makes this visible only before the FIRST ever seed (no cache, no
/// snapshot yet).
class _JobsSkeleton extends StatelessWidget {
  const _JobsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('ai-jobs-loading'),
    physics: const NeverScrollableScrollPhysics(),
    children: [
      for (var i = 0; i < 3; i++)
        const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          title: SizedBox(height: 12),
          subtitle: SizedBox(height: 8),
        ),
    ],
  );
}
