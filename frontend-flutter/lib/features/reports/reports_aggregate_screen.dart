// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../data/report_models.dart';
import '../../l10n/app_localizations_provider.dart';
import 'reports_screen.dart' show ReportPreviewScreen;
import 'reports_aggregate_controller.dart';
import 'reports_aggregate_state.dart';
import 'reports_state.dart';

/// `ReportsAggregateScreen` — the season- or episode-scoped aggregated
/// Soll-Ist report (issue #571, Flutter half).
///
/// Entered with a [ReportsAggregateScope] built from the read DTOs the user
/// is acting on (nav context — never a second projection lookup, client
/// CQRS boundary). Renders the SERVER-derived fields verbatim: rows (one
/// per scene × non-archived shooting day), `is_final` and the wrapped/total
/// day counts. The client never recomputes the aggregate finality rule — a
/// 200-empty report (zero shooting days) renders the standard empty copy.
class ReportsAggregateScreen extends ConsumerWidget {
  const ReportsAggregateScreen({super.key, required this.scope});

  final ReportsAggregateScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(reportsAggregateControllerProvider(scope));
    final controller = ref.read(
      reportsAggregateControllerProvider(scope).notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10nOf(context).reportsAggregateTitle(scope.label)),
      ),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _AggregateBanner(
              key: const Key('aggregate-report-command-error-banner'),
              text: reportErrorCopy(l10nOf(context), error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.accessDenial case final denial?
              when denial.code != 'membership.pending')
            _AggregateBanner(
              key: const Key('aggregate-report-denied'),
              text: reportErrorCopy(l10nOf(context), denial),
              onDismiss: null,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: state.accessDenial == null
                  ? controller.refresh
                  : () async {},
              child: ListView(
                key: const Key('soll-ist-aggregate-screen'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _AggregateSection(state: state, onRetry: controller.refresh),
                  const SizedBox(height: 24),
                  Text(
                    l10nOf(context).reportsPdfSection,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _AggregatePdfCard(
                    cardState: state.pdf ?? const PdfIdle(),
                    gated: state.accessDenial != null,
                    onFetch: controller.fetchPdf,
                    onCancel: controller.cancelPdf,
                    onPreview: () => _openPreview(context, controller),
                    onShare: () => controller.sharePdf(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPreview(
    BuildContext context,
    ReportsAggregateController controller,
  ) async {
    final card = controller.pdfCard();
    if (card is! PdfReady) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReportPreviewScreen(
          filePath: card.file.path,
          title: _pdfFileName(context),
        ),
      ),
    );
    // Preview closed without sharing: the staged temp copy is a non-save
    // exit — delete it and return the card to idle (same D3 contract as
    // the day-scoped preview).
    await controller.dismissPdf();
  }

  String _pdfFileName(BuildContext context) => switch (scope.kind) {
    ReportAggregateScopeKind.season => aggregateReportShareFileName(
      scopeLabel: scope.label,
      kind: AggregateReportPdfKind.seasonSollIst,
    ),
    ReportAggregateScopeKind.episode => aggregateReportShareFileName(
      scopeLabel: scope.label,
      kind: AggregateReportPdfKind.episodeSollIst,
    ),
  };
}

/// On-screen aggregation: server finality verdict, wrapped/total progress,
/// and the scope-true rows.
class _AggregateSection extends StatelessWidget {
  const _AggregateSection({required this.state, required this.onRetry});

  final ReportsAggregateScreenState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10nOf(context).reportsSollIstTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      switch (state.sollIst) {
        AsyncLoading() => const Center(
          child: CircularProgressIndicator(
            key: Key('aggregate-soll-ist-loading'),
          ),
        ),
        AsyncError(:final error) => Center(
          child: Text(
            reportErrorCopy(
              l10nOf(context),
              error is ProblemError
                  ? error
                  : const ProblemError(code: 'unknown'),
            ),
            key: const Key('aggregate-report-error-text'),
          ),
        ),
        AsyncData(:final value) => _AggregateRows(report: value),
      },
    ],
  );
}

/// Rows of the aggregated report with the server's finality verdict and
/// day counts — rendered verbatim.
class _AggregateRows extends StatelessWidget {
  const _AggregateRows({required this.report});

  final AggregateSollIstReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.isFinal)
          Card(
            key: const Key('aggregate-soll-ist-final'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10nOf(context).reportsAggregateFinal),
            ),
          )
        else
          Card(
            key: const Key('aggregate-soll-ist-provisional'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10nOf(context).reportsAggregateProvisional(
                  report.totalShootingDays,
                  report.wrappedShootingDays,
                ),
              ),
            ),
          ),
        if (report.rows.isEmpty) Text(l10nOf(context).reportsNoScenes),
        for (var i = 0; i < report.rows.length; i++)
          _AggregateRowTile(
            key: Key('aggregate-row-$i'),
            row: report.rows[i],
            labelStyle: theme.textTheme.titleSmall,
          ),
      ],
    );
  }
}

/// One aggregated row: day label + scene + flag chips (verbatim server
/// flags — never recomputed client-side).
class _AggregateRowTile extends StatelessWidget {
  const _AggregateRowTile({
    super.key,
    required this.row,
    required this.labelStyle,
  });

  final AggregateSollIstDiffRow row;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final sceneIdShort = row.sceneId.substring(
      0,
      row.sceneId.length <= 8 ? row.sceneId.length : 8,
    );
    final sceneTitle =
        '${row.shootingDayLabel ?? ''} · '
        '${l10n.reportsAggregateSceneLabel(row.sceneNumber ?? sceneIdShort)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sceneTitle, style: labelStyle),
            if (row.scriptDay != null || row.location != null)
              Text(
                [
                  if (row.scriptDay != null)
                    l10n.reportsDayPrefix(row.scriptDay!),
                  if (row.location != null) row.location!,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (row.moved)
                  Chip(
                    key: const Key('aggregate-flag-moved'),
                    label: Text(l10n.reportsFlagMoved),
                  ),
                if (row.missing)
                  Chip(
                    key: const Key('aggregate-flag-missing'),
                    label: Text(l10n.reportsFlagMissing),
                  ),
                if (row.skipped)
                  Chip(
                    key: const Key('aggregate-flag-skipped'),
                    label: Text(l10n.reportsFlagSkipped),
                  ),
                if (row.reshotCandidate)
                  Chip(
                    key: const Key('aggregate-flag-reshot'),
                    label: Text(l10n.reportsFlagReshot),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Aggregate PDF card (one per scope): idle → fetching (progress) → ready
/// (preview/share) → error (code-keyed copy). Reuses [PdfCardState].
class _AggregatePdfCard extends StatelessWidget {
  const _AggregatePdfCard({
    required this.cardState,
    required this.gated,
    required this.onFetch,
    required this.onCancel,
    required this.onPreview,
    required this.onShare,
  });

  final PdfCardState cardState;
  final bool gated;
  final VoidCallback onFetch;
  final VoidCallback onCancel;
  final VoidCallback onPreview;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('aggregate-pdf-card'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10nOf(context).reportsAggregatePdf,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          switch (cardState) {
            PdfIdle() => Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                key: const Key('aggregate-pdf-fetch'),
                onPressed: gated ? null : onFetch,
                child: Text(l10nOf(context).reportsFetch),
              ),
            ),
            PdfFetching() => Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('aggregate-pdf-cancel'),
                onPressed: onCancel,
                child: Text(l10nOf(context).commonCancel),
              ),
            ),
            PdfReady() => Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const Key('aggregate-pdf-preview'),
                  onPressed: onPreview,
                  child: Text(l10nOf(context).reportsPreview),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: const Key('aggregate-pdf-share'),
                  onPressed: onShare,
                  child: Text(l10nOf(context).reportsShare),
                ),
              ],
            ),
            PdfError(:final error) => Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('aggregate-pdf-retry'),
                onPressed: gated ? null : onFetch,
                child: Text(reportErrorCopy(l10nOf(context), error)),
              ),
            ),
          },
        ],
      ),
    ),
  );
}

/// Error/denial banner (code-keyed copy, localized client-side).
class _AggregateBanner extends StatelessWidget {
  const _AggregateBanner({
    super.key,
    required this.text,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                key: const Key('aggregate-report-error-dismiss'),
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
