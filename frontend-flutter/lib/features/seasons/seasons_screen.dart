// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'create_season_sheet.dart';
import 'seasons_controller.dart';
import 'seasons_state.dart';

/// Localized client-side copy for a create-command failure, keyed on the
/// stable problem `code` (AGENTS.md §5 — never branch on / show the server's
/// localized `detail`). Unknown codes fall back to a code-carrying generic.
String createErrorCopy(ProblemError error) => switch (error.code) {
  'seasons.conflict' ||
  'season.conflict' => 'A season with that number already exists.',
  'authz.denied' || 'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the season was not created. Try again.',
  _ => 'The season could not be created (${error.code}).',
};

/// The seasons screen — the reference pattern for every subsequent screen
/// (spec `flutter-first-screen`; AGENTS.md §9).
///
/// A `ConsumerWidget`: it renders and dispatches only (task 3.1, no
/// `StatefulWidget` / `setState`) — all domain branching lives in
/// [SeasonsController] state. The merged row list comes from
/// `SeasonsScreenState.rows`: authoritative rows from the Drift cache,
/// optimistic overlays layered by the controller (never a Drift write).
class SeasonsScreen extends ConsumerWidget {
  const SeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seasonsControllerProvider);
    final rows = state.rows;
    final controller = ref.read(seasonsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Seasons')),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('create-error-banner'),
              text: createErrorCopy(error),
              tone: BannerTone.error,
              onDismiss: controller.dismissCommandError,
              action: const Icon(Icons.close, key: Key('create-error-dismiss')),
            ),
          if (state.isStale)
            _Banner(
              key: const Key('seasons-stale-banner'),
              text: 'Cached data may be outdated',
              tone: BannerTone.warning,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: rows.isEmpty
                  ? ListView(
                      key: const Key('seasons-list'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 160),
                        Center(child: Text('No seasons yet')),
                      ],
                    )
                  : ListView.builder(
                      key: const Key('seasons-list'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _SeasonTile(row: rows[i]),
                    ),
            ),
          ),
        ],
      ),
      // AUTHZ-GATE: the backend `create_season` handler requires an
      // authenticated caller (CurrentUser extractor; auth-only — there is
      // no season-membership role to check for a season that does not
      // exist yet). The FAB is therefore shown only for a resolved
      // authenticated session; loading and error states show nothing
      // (the request would be refused server-side anyway).
      floatingActionButton: _canCreateSeason(ref)
          ? FloatingActionButton(
              key: const Key('season-add-fab'),
              onPressed: () => showCreateSeasonSheet(context, ref),
              tooltip: 'Add season',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreateSeason(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }
}

class _SeasonTile extends StatelessWidget {
  const _SeasonTile({required this.row});

  final SeasonRow row;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedSeasonRow(:final season) => ListTile(
      key: Key('season-${season.id}'),
      title: Text(season.title ?? 'Season ${season.number}'),
      subtitle: Text('Number ${season.number}'),
    ),
    OptimisticSeasonRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      title: Text(
        overlay.name?.isNotEmpty == true
            ? overlay.name!
            : 'Season ${overlay.number ?? ''}',
      ),
      subtitle: Text(
        overlay.status == OverlayStatus.stale
            ? (overlay.warning ?? kReconcileStaleWarning)
            : 'Just created — syncing…',
      ),
      trailing: overlay.status == OverlayStatus.stale
          ? const Icon(Icons.cloud_off, key: Key('overlay-warning'))
          : const SizedBox(
              key: Key('overlay-spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    ),
  };
}

enum BannerTone { warning, error }

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.tone,
    this.onDismiss,
    this.action,
  });

  final String text;
  final BannerTone tone;
  final VoidCallback? onDismiss;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = switch (tone) {
      BannerTone.warning => scheme.tertiaryContainer,
      BannerTone.error => scheme.errorContainer,
    };
    final foreground = switch (tone) {
      BannerTone.warning => scheme.onTertiaryContainer,
      BannerTone.error => scheme.onErrorContainer,
    };
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
            if (action != null)
              GestureDetector(
                onTap: onDismiss,
                child: IconTheme(
                  data: IconThemeData(color: foreground),
                  child: action!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
