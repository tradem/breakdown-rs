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
import 'reports_index_controller.dart';
import 'reports_index_state.dart';
import 'reports_screen.dart';
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

    return Scaffold(
      appBar: AppBar(title: ReportsIndexTitle(episodeLabel: episodeLabel)),
      body: Column(
        children: [
          if (state.gateDenial case final denial?
              when denial.code != 'membership.pending')
            _IndexDenialBanner(
              key: const Key('reports-index-denied'),
              denial: denial,
            ),
          if (state.isStale && state.commandError == null)
            _Banner(
              key: const Key('report-index-stale-banner'),
              text: l10n.shootingDaysStaleBanner,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => controller.refresh(episode.id),
              child: _IndexList(
                state: state,
                episode: episode,
                seasonId: seasonId,
                onRetry: () => controller.refresh(episode.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexList extends StatelessWidget {
  const _IndexList({
    required this.state,
    required this.episode,
    required this.seasonId,
    required this.onRetry,
  });

  final ReportsIndexScreenState state;
  final EpisodeView episode;
  final String seasonId;

  /// Re-enters the SHARED day-list controller — the index has no fetch of
  /// its own (design decision 2).
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final rows = state.rows;
    // Error state keyed on the stable problem `code`, with cached rows
    // kept visible and stale-indicated on a failed refresh (spec: the
    // index inherits the day list's projection-lag semantics unchanged).
    if (state.commandError case final error? when rows.isEmpty) {
      return _IndexErrorView(code: error.code, onRetry: onRetry);
    }
    if (rows.isEmpty) {
      return ListView(
        key: const Key('reports-index-screen'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 160), ReportIndexEmptyView()],
      );
    }
    return ListView.builder(
      key: const Key('reports-index-screen'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return ReportIndexDayTile(
          day: row.day,
          finality: row.finality,
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReportsScreen(day: row.day, seasonId: seasonId),
            ),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text});

  final String text;

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
          ],
        ),
      ),
    );
  }
}

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
