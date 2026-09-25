// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../data/report_models.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reports_controller.dart';
import 'reports_state.dart';

/// `ReportsScreen` — the day-context reporting surface (Phase 4).
///
/// Entered from the Phase 2 day screen ("Reports" action) with the acted-on
/// [day] read DTO and the [seasonId] scoping the membership gate. All
/// command context comes from these — never from a second projection
/// lookup (CQRS boundary).
///
/// Content (read-model render only, D2):
/// - **Soll-Ist on-screen report** from the JSON report routes: planned vs
///   actual counts (dispo / shoot-day row counts), per-row flag chips
///   (`moved/missing/skipped/reshot`) and the finality banner from the
///   report DTO. The client renders chips/rows verbatim and never
///   recomputes flags or finality; unknown status/flag values strict-reject
///   to the standard error state.
/// - **PDF cards** (dispo / shoot-day / planned-vs-actual): user-initiated
///   fetch with progress, in-app FOSS preview (`pdfrx`), share/save via the
///   platform sheet. PDF bytes never enter Drift.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key, required this.day, required this.seasonId});

  final ShootingDayView day;
  final String seasonId;

  ReportDayScope get _scope =>
      ReportDayScope(dayId: day.id, seasonId: seasonId);

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
    final scope = _scope;
    final state = ref.watch(reportsControllerProvider(scope));
    final controller = ref.read(reportsControllerProvider(scope).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10nOf(context)
              .reportsTitle(day.label ?? l10nOf(context).sceneShootDayFallback),
        ),
      ),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('reports-command-error-banner'),
              text: reportErrorCopy(l10nOf(context), error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.accessDenial case final denial?
              when denial.code != 'membership.pending')
            _DenialBanner(
              key: const Key('reports-denied'),
              denial: denial,
              onRetry: denial.code == 'membership.unavailable'
                  ? () => controller.retryAccess()
                  : null,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                key: const Key('soll-ist-report-screen'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _SollIstSection(state: state, onRetry: controller.refresh),
                  const SizedBox(height: 24),
                  Text(
                    l10nOf(context).reportsPdfSection,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final kind in ReportPdfKind.values)
                    _PdfCard(
                      kind: kind,
                      cardState: state.pdfs[kind] ?? const PdfIdle(),
                      gated: state.accessDenial != null,
                      onFetch: () => controller.fetchPdf(kind),
                      onCancel: () => controller.cancelPdf(kind),
                      onPreview: () => _openPreview(context, controller, kind),
                      onShare: () => controller.sharePdf(kind),
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
    ReportsController controller,
    ReportPdfKind kind,
  ) async {
    final card = controller.pdfCard(kind);
    if (card is! PdfReady) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReportPreviewScreen(
          filePath: card.file.path,
          title: reportShareFileName(dayLabel: day.label ?? day.id, kind: kind),
        ),
      ),
    );
    // Preview closed without sharing: the staged temp copy is a non-save
    // exit — delete it and return the card to idle (D3).
    // Handled: dismissal cannot fail visibly; the cache layer is best-effort.
    await controller.dismissPdf(kind);
  }
}

/// On-screen Soll-Ist report: counts, finality banner, flag rows.
class _SollIstSection extends StatelessWidget {
  const _SollIstSection({required this.state, required this.onRetry});

  final ReportsScreenState state;
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
      _CountsRow(state: state),
      const SizedBox(height: 8),
      switch (state.sollIst) {
        AsyncLoading() => const Center(
          child: CircularProgressIndicator(key: Key('soll-ist-loading')),
        ),
        AsyncError(:final error) => _ReportsErrorView(
          code: error is ProblemError ? error.code : 'unknown',
          onRetry: onRetry,
        ),
        AsyncData(:final value) => _SollIstRows(report: value),
      },
    ],
  );
}

/// Planned/actual scene counts over the dispo / shoot-day read DTOs.
///
/// The keyed number widgets carry the bare count text only (the Gherkin
/// steps parse them as integers) — labels render as siblings.
class _CountsRow extends StatelessWidget {
  const _CountsRow({required this.state});

  final ReportsScreenState state;

  @override
  Widget build(BuildContext context) {
    final planned = state.plannedCount;
    final actual = state.actualCount;
    if (planned is AsyncData<int> && actual is AsyncData<int>) {
      return Row(
        key: const Key('soll-ist-counts'),
        children: [
          Text(l10nOf(context).reportsPlannedLabel),
          Text('${planned.value}', key: const Key('soll-ist-planned')),
          const SizedBox(width: 16),
          Text(l10nOf(context).reportsActualLabel),
          Text('${actual.value}', key: const Key('soll-ist-actual')),
        ],
      );
    }
    if (planned is AsyncError || actual is AsyncError) {
      return Text(
        l10nOf(context).reportsCountsUnavailable,
        key: const Key('reports-counts-error'),
      );
    }
    return const Text('—', key: Key('soll-ist-counts-loading'));
  }
}

/// Soll-Ist rows with server-derived flag chips, verbatim (D2).
class _SollIstRows extends StatelessWidget {
  const _SollIstRows({required this.report});

  final SollIstReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.isFinal)
          Card(
            key: const Key('soll-ist-final'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10nOf(context).reportsFinal),
            ),
          ),
        if (report.rows.isEmpty) Text(l10nOf(context).reportsNoScenes),
        for (final row in report.rows)
          Card(
            key: Key('soll-ist-row-${row.sceneId}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10nOf(context).sceneTileLabel(
                      row.sceneNumber != null
                          ? '$row.sceneNumber'
                          : (row.sceneId.length > 8
                                ? row.sceneId.substring(0, 8)
                                : row.sceneId),
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (row.scriptDay != null || row.location != null)
                    Text(
                      [
                        if (row.scriptDay != null)
                          l10nOf(context).reportsDayPrefix('$row.scriptDay'),
                        if (row.location != null) row.location!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (row.moved)
                        Chip(
                          key: const Key('soll-ist-flag-moved'),
                          label: Text(l10nOf(context).reportsFlagMoved),
                        ),
                      if (row.missing)
                        Chip(
                          key: const Key('soll-ist-flag-missing'),
                          label: Text(l10nOf(context).reportsFlagMissing),
                        ),
                      if (row.skipped)
                        Chip(
                          key: const Key('soll-ist-flag-skipped'),
                          label: Text(l10nOf(context).reportsFlagSkipped),
                        ),
                      if (row.reshotCandidate)
                        Chip(
                          key: const Key('soll-ist-flag-reshot'),
                          label: Text(l10nOf(context).reportsFlagReshot),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One PDF card: idle → fetching (progress) → ready (preview/share) →
/// error (code-keyed copy + retry). Fetch is user-initiated only.
class _PdfCard extends StatelessWidget {
  const _PdfCard({
    required this.kind,
    required this.cardState,
    required this.gated,
    required this.onFetch,
    required this.onCancel,
    required this.onPreview,
    required this.onShare,
  });

  final ReportPdfKind kind;
  final PdfCardState cardState;
  final bool gated;
  final VoidCallback onFetch;
  final VoidCallback onCancel;
  final VoidCallback onPreview;
  final VoidCallback onShare;

  String _title(AppLocalizations l10n) => switch (kind) {
    ReportPdfKind.dispo => l10n.reportsPdfDispo,
    ReportPdfKind.shootDay => l10n.reportsPdfShootDay,
    ReportPdfKind.plannedVsActual => l10n.reportsPdfPlannedVsActual,
  };

  @override
  Widget build(BuildContext context) => Card(
    key: Key('report-pdf-card-${kind.name}'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title(l10nOf(context)),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          switch (cardState) {
            PdfIdle() => Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                key: Key('report-pdf-fetch-${kind.name}'),
                onPressed: gated ? null : onFetch,
                child: Text(l10nOf(context).reportsFetch),
              ),
            ),
            PdfFetching(:final progress) => Column(
              children: [
                if (progress != null)
                  LinearProgressIndicator(
                    key: Key('report-pdf-progress-${kind.name}'),
                    value: progress,
                  )
                else
                  LinearProgressIndicator(
                    key: Key('report-pdf-progress-${kind.name}'),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: Key('report-pdf-cancel-${kind.name}'),
                    onPressed: onCancel,
                    child: Text(l10nOf(context).commonCancel),
                  ),
                ),
              ],
            ),
            PdfReady() => Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('report-pdf-preview-${kind.name}'),
                  onPressed: onPreview,
                  child: Text(l10nOf(context).reportsPreview),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: Key('report-pdf-share-${kind.name}'),
                  onPressed: gated ? null : onShare,
                  child: Text(l10nOf(context).reportsShare),
                ),
              ],
            ),
            PdfError(:final error) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reportErrorCopy(l10nOf(context), error),
                  key: Key('report-pdf-error-${kind.name}'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: Key('report-pdf-retry-${kind.name}'),
                    onPressed: gated ? null : onFetch,
                    child: Text(l10nOf(context).commonRetry),
                  ),
                ),
              ],
            ),
          },
        ],
      ),
    ),
  );
}

/// In-app PDF preview (FOSS renderer `pdfrx`, zoom/pan built in).
/// The viewer chrome follows the app theme; the staged temp file is owned
/// by the controller and deleted when this route pops without sharing.
class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  final String filePath;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PdfViewer.file(
      filePath,
      key: const Key('report-pdf-viewer'),
      params: PdfViewerParams(
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                onPressed: onDismiss,
                color: scheme.onErrorContainer,
                tooltip: l10nOf(context).episodesDismiss,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

/// Client-side AUTHZ-GATE denial narrative (localized 403 copy keyed on the
/// stable problem `code`): rendered BEFORE any report request leaves the
/// device; the request count stays zero.
class _DenialBanner extends StatelessWidget {
  const _DenialBanner({super.key, required this.denial, required this.onRetry});

  final ProblemError denial;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reportErrorCopy(l10nOf(context), denial),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onRetry != null)
              TextButton(
                key: const Key('reports-denied-retry'),
                onPressed: onRetry,
                child: Text(
                  l10nOf(context).commonRetry,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportsErrorView extends StatelessWidget {
  const _ReportsErrorView({required this.code, required this.onRetry});

  final String code;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          reportErrorCopy(l10nOf(context), ProblemError(code: code)),
          key: const Key('reports-error'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          key: const Key('reports-retry'),
          onPressed: () => onRetry(),
          child: Text(l10nOf(context).commonRetry),
        ),
      ],
    ),
  );
}
