// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/locale_formatters.dart';
import '../reports_index_state.dart';

/// Pure presentation trees for `ReportsIndexScreen`: plain data + callbacks
/// in, widgets out — no Riverpod imports, theme roles only, semantic keys
/// for `find.text`-paired tests. Rows render the day list's server order
/// exactly (no client re-sort), and NO report content is ever rendered
/// here (spec `flutter-reports-index`: Szenen rows, flag chips, counts and
/// PDF affordances live only on the day-scoped report screen).

/// The report index app-bar title.
class ReportsIndexTitle extends StatelessWidget {
  const ReportsIndexTitle({super.key, required this.episodeLabel});

  /// The acted-on episode's label (its name or "Episode N") — nav context
  /// from the scope, never a lookup.
  final String episodeLabel;

  @override
  Widget build(BuildContext context) =>
      Text(l10nOf(context).reportsIndexTitle(episodeLabel));
}

/// One index row: the day's own label, its date and the per-day finality
/// chip. A single tap target pushing the day-scoped report screen.
class ReportIndexDayTile extends StatelessWidget {
  const ReportIndexDayTile({
    super.key,
    required this.day,
    required this.finality,
    this.onOpen,
  });

  /// The projected `ShootingDayView` — label, date and `wrappedAt` all
  /// come from this read DTO the day list already holds.
  final ShootingDayView day;

  /// The per-day finality, derived in one place from the day's
  /// `wrappedAt` (never recomputed here).
  final ReportDayFinality finality;

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return ListTile(
      key: Key('report-index-day-${day.id}'),
      minTileHeight: 48,
      onTap: onOpen,
      title: Text(
        day.label ?? l10n.shootingDayUntitled,
        key: Key('report-index-day-label-${day.id}'),
      ),
      subtitle: day.date == null
          ? null
          : Text(
              // Framework locale data performs the date formatting; no
              // hand-rolled locale math (spec §5).
              formatMediumDate(context, day.date!.toDateTime()),
            ),
      trailing: ReportIndexFinalityChip(finality: finality, dayId: day.id),
    );
  }
}

/// Per-day finality chip: `abschließend` when the day's `wrappedAt` is
/// present, `offen` otherwise — a short state, deliberately a distinct key
/// from the report screen's full-sentence `reportsFinal` banner.
class ReportIndexFinalityChip extends StatelessWidget {
  const ReportIndexFinalityChip({
    super.key,
    required this.finality,
    required this.dayId,
  });

  final ReportDayFinality finality;
  final String dayId;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final label = switch (finality) {
      ReportDayFinality.wrapped => l10n.reportsIndexDayFinal,
      ReportDayFinality.open => l10n.reportsIndexDayOpen,
    };
    return Chip(
      key: Key('report-index-finality-$dayId'),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Empty state for a day-less scope: names the Soll/Ist report as what
/// becomes available once a shooting day is planned — and offers NO
/// report affordance, because the report routes are day-scoped in the
/// contract itself.
///
/// This is the CONFIRMED-empty surface: it renders only once the day list
/// resolved with no days. While the list is loading or a day is still an
/// optimistic overlay, [ReportIndexLoadingView] / [ReportIndexPendingView]
/// stand in instead — an un-loaded or pending scope is not an empty scope.
class ReportIndexEmptyView extends StatelessWidget {
  const ReportIndexEmptyView({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.summarize_outlined, size: 48),
        const SizedBox(height: 8),
        Text(
          l10nOf(context).reportsIndexEmpty,
          key: const Key('report-index-empty'),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

/// The scrollable host for the confirmed-empty state (stays pull-to-
/// refreshable so a stale cache can be reconciled).
class ReportIndexEmptyList extends StatelessWidget {
  const ReportIndexEmptyList({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('reports-index-screen'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [SizedBox(height: 160), ReportIndexEmptyView()],
  );
}

/// Initial-load state: the day list has not resolved yet, so the index has
/// nothing to say about this scope's days — a progress indicator, never the
/// confirmed-empty copy.
class ReportIndexLoadingView extends StatelessWidget {
  const ReportIndexLoadingView({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('reports-index-loading'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      SizedBox(height: 160),
      Center(
        child: CircularProgressIndicator(
          key: Key('reports-index-loading-spinner'),
        ),
      ),
    ],
  );
}

/// Pending state for a scope whose only days are optimistic
/// acknowledgements: no row is listed (an unprojected day has no
/// server-derived `wrappedAt`, so no honest finality), and the day list's
/// syncing copy + spinner stands in for both a row and the empty state.
class ReportIndexPendingView extends StatelessWidget {
  const ReportIndexPendingView({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('reports-index-pending'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                key: Key('reports-index-pending-spinner'),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 8),
            // The day list's own syncing copy — the same narrative the
            // overlay row shows where the user watches it reconcile.
            Text(
              l10nOf(context).seasonsSyncing,
              key: const Key('reports-index-pending-text'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ],
  );
}
