// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../data/report_models.dart';
import '../../l10n/app_localizations_provider.dart';
import 'reports_index_controller.dart';
import 'reports_index_state.dart';
import 'reports_screen.dart';
import 'reports_aggregate_screen.dart';
import 'reports_aggregate_state.dart';
import 'widgets/reports_aggregate_entry.dart';
import 'widgets/reports_index_widgets.dart';

/// `ReportsIndexScreen` — the episode's report index (a navigation
/// surface, not a second report).
///
/// Entered from the shooting-days screen's labelled reports action with the
/// acted-on [episode] read DTO and the threaded parent [seasonId] (nav
/// context — never a second projection lookup, client CQRS boundary).
///
/// Lists the episode's PROJECTED shooting days in the day list's server
/// order (`order_key ASC` — never re-sorted client-side), each row with its
/// own label, date and per-day `abschließend`/`offen` state read directly
/// from that day's `wrapped_at`. A row tap pushes the EXISTING day-scoped
/// `ReportsScreen` for that day — the index renders NO report content:
/// no Soll/Ist rows, no flag chips, no counts, no PDF cards (the
/// day-scoped report screen stays the only renderer of report data).
///
/// Zero network traffic of its own: rows come from the existing
/// `shootingDaysControllerProvider(episodeId)` state, and the gate is a
/// pure local pre-check for the destination screen.
class ReportsIndexScreen extends ConsumerWidget {
  const ReportsIndexScreen({
    super.key,
    required this.episode,
    required this.seasonId,
  });

  final EpisodeView episode;
  final String seasonId;

  ReportIndexScope get _scope =>
      ReportIndexScope(episodeId: episode.id, seasonId: seasonId);

  /// Pushes the episode-scope aggregate screen. The gate is re-checked
  /// here (AUTHZ-GATE): the entry never navigates while the gate denies
  /// or is unresolved — zero requests, no gated navigation. The push is
  /// the method's expression value (VoidCallback coerces — intentional
  /// fire-and-forget navigation, never a discarded Future statement).
  Future<void> _openAggregate(
    BuildContext context, {
    required bool gateOpen,
  }) async {
    if (!gateOpen) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsAggregateScreen(
          scope: ReportsAggregateScope(
            kind: ReportAggregateScopeKind.episode,
            id: episode.id,
            seasonId: seasonId,
            label:
                episode.name ??
                l10nOf(context).episodeTileLabel(episode.number),
          ),
        ),
      ),
    );
  }

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
    final state = ref.watch(reportsIndexControllerProvider(scope));
    final controller = ref.read(reportsIndexControllerProvider(scope).notifier);
    final l10n = l10nOf(context);
    final episodeLabel = episode.name ?? l10n.episodeTileLabel(episode.number);
    // AUTHZ-GATE: every network-triggering affordance on this screen is
    // disabled while the gate is denied or unresolved — a denied scope
    // issues ZERO requests and never enters a day report.
    final gateOpen = state.gateOpen;
    Future<void> refresh() => controller.refresh(episode.id);

    // The width-resolved aggregate entry needs the scaffold's viewport
    // width (the #549 pattern): LayoutBuilder wraps the Scaffold, never
    // the unbounded action slot.
    return LayoutBuilder(
      builder: (context, constraints) => Scaffold(
        appBar: AppBar(
          title: ReportsIndexTitle(episodeLabel: episodeLabel),
          // Episode-level aggregated Soll-Ist entry (issue #571): labelled
          // per the visible-label norm; pushes the episode-scope aggregate
          // screen with the acted-on [episode] as nav context.
          actions: [
            ReportsAggregateAppBarAction(
              baseKey: 'reportsIndexAggregateOpen',
              roomForLabel: constraints.maxWidth >= 300,
              onOpen: () => _openAggregate(context, gateOpen: gateOpen),
            ),
          ],
        ),
        body: Column(
          children: [
            if (state.gateDenial case final denial?
                when denial.code != 'membership.pending')
              _IndexDenialBanner(
                key: const Key('reports-index-denied'),
                denial: denial,
              ),
            // Stale stays visible whenever the day list says so — including
            // alongside a fetch failure, so retained cached rows are never
            // rendered as if they were current.
            if (state.isStale)
              _Banner(
                key: const Key('report-index-stale-banner'),
                text: l10n.shootingDaysStaleBanner,
              ),
            // A pending (unprojected) day alongside projected rows: the index
            // lists no row for it, so it says so in the banner instead. When
            // NO row exists yet the body itself carries the pending indicator
            // (see `_IndexList`), so the copy is never duplicated.
            if (state.hasPendingOverlay && state.rows.isNotEmpty)
              _Banner(
                key: const Key('report-index-pending-banner'),
                text: l10n.seasonsSyncing,
                tone: _BannerTone.info,
              ),
            Expanded(
              child: _IndexList(
                state: state,
                episode: episode,
                seasonId: seasonId,
                gateOpen: gateOpen,
                onRefresh: gateOpen ? refresh : null,
                onRetry: gateOpen ? refresh : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexList extends StatelessWidget {
  const _IndexList({
    required this.state,
    required this.episode,
    required this.seasonId,
    required this.gateOpen,
    required this.onRefresh,
    required this.onRetry,
  });

  final ReportsIndexScreenState state;
  final EpisodeView episode;
  final String seasonId;

  /// Whether the client-side AUTHZ-GATE passes. When `false`, pull-to-
  /// refresh, the retry affordance and every row's navigation target are
  /// all disabled — the index issues zero requests on denial and never
  /// pushes the day-scoped report screen.
  final bool gateOpen;

  /// The SHARED day-list refresh, or `null` while the AUTHZ-GATE denies:
  /// a denied scope must not pull the day list.
  final Future<void> Function()? onRefresh;

  /// Re-enters the SHARED day-list controller — the index has no fetch of
  /// its own (design decision 2). `null` on gate denial.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final rows = state.rows;
    Widget list;
    if (rows.isNotEmpty) {
      list = ListView.builder(
        key: const Key('reports-index-screen'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          return ReportIndexDayTile(
            day: row.day,
            finality: row.finality,
            // On gate denial the row loses its navigation target entirely:
            // no push into the day-scoped report screen.
            onOpen: gateOpen
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReportsScreen(day: row.day, seasonId: seasonId),
                    ),
                  )
                : null,
          );
        },
      );
    } else if (state.isLoading) {
      // Not loaded yet — an empty row list here is NOT "confirmed empty".
      list = const ReportIndexLoadingView();
    } else if (state.hasPendingOverlay) {
      // A day exists only as an optimistic acknowledgement: no row, no
      // confirmed-empty copy — the pending indicator stands in (spec
      // `flutter-reports-index`, "A pending day is not listed").
      list = const ReportIndexPendingView();
    } else if (state.commandError case final error?) {
      // Error state keyed on the stable problem `code`; cached rows stay
      // visible and stale-indicated on a failed refresh (the index inherits
      // the day list's projection-lag semantics unchanged).
      list = _IndexErrorView(code: error.code, onRetry: onRetry);
    } else {
      list = const ReportIndexEmptyList();
    }

    // Pull-to-refresh exists only while the gate passes: a denied or
    // unresolved scope issues no day-list request.
    if (onRefresh case final allowed?) {
      list = RefreshIndicator(onRefresh: allowed, child: list);
    }
    return list;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.tone = _BannerTone.error});

  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color container, Color onContainer) = switch (tone) {
      _BannerTone.error => (scheme.errorContainer, scheme.onErrorContainer),
      _BannerTone.info => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return ColoredBox(
      color: container,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (tone == _BannerTone.info) ...[
              const Icon(Icons.sync, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(text, style: TextStyle(color: onContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner emphasis: a failure reads in the error container, a
/// reconciliation-pending notice in the neutral surface container (a pending
/// day is not an error).
enum _BannerTone { error, info }

/// Client-side AUTHZ-GATE denial narrative for the index (localized 403
/// copy keyed on the stable problem `code`): rendered with ZERO requests —
/// the gate is a pre-check for the destination screen, and the index
/// itself fetches no protected data.
class _IndexDenialBanner extends StatelessWidget {
  const _IndexDenialBanner({super.key, required this.denial});

  final ProblemError denial;

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
          ],
        ),
      ),
    );
  }
}

class _IndexErrorView extends StatelessWidget {
  const _IndexErrorView({required this.code, this.onRetry});

  final String code;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('reports-index-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(
        child: Text(
          // Keyed on the stable problem `code` — never the server's
          // localized `detail`.
          reportErrorCopy(l10nOf(context), ProblemError(code: code)),
          key: const Key('reports-index-error-text'),
        ),
      ),
      const SizedBox(height: 8),
      if (onRetry != null)
        Center(
          child: FilledButton.tonal(
            key: const Key('reports-index-retry'),
            onPressed: () => onRetry!(),
            child: Text(l10nOf(context).commonRetry),
          ),
        ),
    ],
  );
}
