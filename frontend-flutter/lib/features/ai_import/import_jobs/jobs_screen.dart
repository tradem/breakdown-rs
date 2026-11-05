// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/spacing.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../clippy/clippy_trigger.dart';
import '../clippy/karl_kleiderbuegel_overlay.dart';
import '../../../l10n/locale_formatters.dart';
import '../../../data/ai_import_providers.dart';
import '../../../design/components/breakdown_app_bar.dart';
import '../../../design/components/plus_action_fab.dart';
import '../../../auth/auth_providers.dart';
import '../../shell/quick_create_sheet.dart'
    show aiImportJobsQuickCreateActions, showQuickCreateSheet;
import 'job_cost_card.dart' show aiJobCostMetricIcon;
import 'job_status_screen.dart';
import 'import_state.dart' show aiJobStageCopy;
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
///
/// Issue #823: the screen is the SECOND home of the plus action (the Script
/// destination is the first). Its sheet carries exactly ONE entry —
/// „Import" — because the import is the only thing this surface creates, and
/// the FAB is labelled with that entry (`navAiImport`) instead of the shell's
/// generic „Erstellen". The empty state carries no CTA: the FAB is the
/// screen's single create path in every list state.
class AiImportJobsScreen extends ConsumerWidget {
  const AiImportJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final state = ref.watch(aiImportJobsView);
    final loading =
        ref.watch(aiImportJobsViewControllerProvider).isLoading &&
        state.rows.isEmpty;

    // AUTHZ-GATE (issue #823, client-side mirror of the backend's
    // handler-internal authorization — Decision D6): opening the quick-create
    // sheet is `Requirement::Authenticated`-gated UI, because every flow it
    // deep-links (the AI-import submit included) is auth-gated server-side.
    // A pending, erroring or signed-out session renders NO Import action (the
    // same rule the shell's plus action and the seasons FAB follow); the
    // pushed submit controller re-gates before any network call, and the
    // sheet itself issues no request.
    final session = ref.watch(authSessionControllerProvider);
    final canImport = session is AsyncData && session.value != null;

    // Karl Kleiderbügel flow state (issue #516): derived ONLY from this
    // screen's own watched state — never from a second projection call.
    final clippyState = state.error != null && state.rows.isEmpty
        ? ClippyFlowState.error
        : state.rows.any((r) => r.status == JobStatus.running)
        ? ClippyFlowState.running
        : state.rows.any((r) => r.status == JobStatus.pending)
        ? ClippyFlowState.queued
        : ClippyFlowState.idle;

    // The FAB's own clearance band keeps the list's last row out from under
    // it (the same 80 dp the shell reserves for its compact FAB, issue
    // #623): the jobs screen floats the action over a full-width list in
    // every window class, so the band is applied unconditionally — but only
    // while the action itself renders (auth-gate symmetry).
    //
    // The system's bottom inset is ADDED to the constant (CodeRabbit review
    // on #848): this Scaffold has no bottom bar, so its body runs to the
    // PHYSICAL bottom, while the floating FAB keeps `kFloatingActionButtonMargin`
    // PLUS `viewPadding.bottom` above it (the `FabFloatOffsetY` safe margin).
    // Without the inset the band ends 8 dp above the FAB's top edge only on a
    // gesture-bar-free device; on a device with a >8 dp bottom inset the last
    // row (and its trailing delete action) stayed under the FAB. The shell's
    // docked FAB needs no such addend: its `bottomNavigationBar` already
    // consumes the inset, so the compact band is measured from the bar's top.
    final bottomClearance = canImport
        ? kPlusActionFabBottomClearance +
              MediaQuery.viewPaddingOf(context).bottom
        : 0.0;

    return Scaffold(
      appBar: BreakdownAppBar(title: l10n.aiJobsTitle),
      // The screen's plus action (issue #823): own key, own label — its
      // sheet has one entry, so it is named after what it does.
      floatingActionButton: canImport
          ? PlusActionFab(
              fabKey: const Key('ai-jobs-plus-fab'),
              label: l10n.navAiImport,
              onPressed: () => unawaited(
                showQuickCreateSheet(
                  context,
                  actions: aiImportJobsQuickCreateActions(l10n),
                ),
              ),
            )
          : null,
      body: KarlKleiderbuegelOverlay(
        flowState: clippyState,
        // Issue #823: reserve the plus action's band below the content in
        // EVERY list state (empty, loading, data, error), so the floating
        // FAB never covers a row — the same clearance the shell's docked
        // FAB reserves (issue #623). The overlay's Karl bubble sits
        // bottom-LEADING and stays clear of the action.
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomClearance),
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
class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job});

  final AiImportJobRowView job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // The compact cost line (issue #675): primary figure per the user's
    // `cost_display_preference` — never `0` for unknown pricing.
    final costLine = aiJobCostCompactCopy(
      l10n,
      job.cost,
      ref.watch(aiCostDisplayPreferenceProvider),
    );
    // Row identity (issue #763): the document's name and the imported
    // episode(s) when the server reported them, today's kind/date otherwise.
    // Pure decision — see `aiJobRowIdentity`.
    final identity = aiJobRowIdentity(
      l10n,
      job,
      kind: kind,
      date: formatMediumDate(context, job.createdAt),
    );

    return ListTile(
      key: Key('ai-jobs-row-${job.id}'),
      leading: Icon(jobStatusIcon(job.status), color: statusColor),
      title: Text(
        identity.title,
        key: Key('ai-jobs-row-title-${job.id}'),
        // A file name can be long: two lines, then ellipsized. The row is a
        // navigation target, not a place to wrap into paragraphs.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (identity.secondary != null)
            Text(
              identity.secondary!,
              key: Key('ai-jobs-row-identity-${job.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(job.statusLabel(l10n), key: Key('ai-jobs-row-status-${job.id}')),
          // Issue #800: a preview that has already been imported says so, so a
          // re-apply never looks like the first one. The server owns the fact
          // (`AiImportJob.applied`); the row renders it or nothing.
          if (job.isAlreadyImported)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space4),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.space4),
                  Expanded(
                    child: Text(
                      l10n.aiJobsRowAlreadyImported,
                      key: Key('ai-jobs-row-applied-${job.id}'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          // Compact stage/episode progress summary (issue #664): from the
          // fetched row's progress — the list screen never opens an SSE
          // stream (zero watches, #547 battery contract).
          //
          // Gated on the STATUS, never on `progress != null` (issue #763): a
          // finished job must not advertise the stage it died at, and the label
          // only renders with the values it names.
          if (job.showsLiveProgress) ...[
            Text(
              key: Key('ai-jobs-row-stage-${job.id}'),
              aiJobStageCopy(l10n, job.progress!.stage),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (job.progress!.episodesSeen?.isNotEmpty ?? false)
              Text(
                key: Key('ai-jobs-row-episodes-${job.id}'),
                l10n.aiJobEpisodesSeenValues(
                  job.progress!.episodesSeen!.join(', '),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          if (costLine != null)
            // Compact cost line (issue #675) with its metric glyph (issue
            // #761): the icon reinforces the always-visible "Kosten: …" text
            // and mirrors the job card's hero choice, so list and detail
            // agree on which figure is primary (glossary: never icon-only).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  aiJobCostMetricIcon(
                    job.cost,
                    ref.watch(aiCostDisplayPreferenceProvider),
                  ),
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.space8),
                Expanded(
                  child: Text(
                    costLine,
                    key: Key('ai-jobs-row-cost-${job.id}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          // Degraded-extraction line (issue #758): rows the extraction could
          // only rebuild from the document heading are named here, so a
          // short-on-content import never passes for a clean one.
          if (job.hasSynthesizedScenes)
            Text(
              l10n.aiJobsRowScenesRebuilt('${job.scenesSynthesized}'),
              key: Key('ai-jobs-row-scenes-rebuilt-${job.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
      trailing: _JobRowTrailing(job: job),
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

/// The row's trailing affordances (issue #671): the retained error
/// presence indicator, a delete icon on `dead_letter` rows only, and the
/// navigation chevron. Terminal-failure rows without the delete stay
/// unchanged; non-terminal rows never render the affordance.
class _JobRowTrailing extends ConsumerWidget {
  const _JobRowTrailing({required this.job});

  final AiImportJobRowView job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[
      if (job.hasLastError) Icon(Icons.error_outline, color: scheme.error),
      // Delete affordance on dead-letter rows ONLY (issue #671): a stuck
      // failed import is the dead end this closes. The confirm dialog
      // names the dedup-lock release — the feature's point for testing
      // workflows.
      if (job.isDeletable)
        IconButton(
          key: Key('ai-jobs-row-delete-${job.id}'),
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.aiJobsDeleteTooltip,
          onPressed: () => unawaited(_confirmDelete(context, ref)),
        ),
      const Icon(Icons.chevron_right),
    ];
    if (children.length == 1) return children.single;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// Confirm dialog, then dispatch through the view controller. A failed
  /// delete surfaces as a SnackBar keyed on the stable problem `code`
  /// (the #665 class — a readable message, never a silent failure); a
  /// successful one is already visible (the controller's reconcile
  /// refetch drops the row).
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = l10nOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiJobsDeleteConfirmTitle),
        content: Text(l10n.aiJobsDeleteConfirmBody),
        actions: [
          TextButton(
            key: const Key('ai-jobs-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.aiJobsDeleteConfirmCancel),
          ),
          FilledButton(
            key: const Key('ai-jobs-delete-confirm'),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext)
                  .colorScheme
                  .onErrorContainer,
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.aiJobsDeleteConfirmDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(aiImportJobsViewControllerProvider.notifier)
        .deleteJob(job.id);
    final error = result.getLeft().toNullable();
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('ai-jobs-delete-error'),
        content: Text(aiJobsDeleteErrorCopy(l10n, error)),
      ),
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

/// Honest empty state: "no import yet" — plain narrative. The screen's
/// plus action (issue #823) is the single path into the import entry in
/// EVERY list state, so the former empty-state CTA was a second path to the
/// same flow and is gone.
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
