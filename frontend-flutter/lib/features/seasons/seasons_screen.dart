// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../app_info/info_dialog.dart';
import '../app_info/settings_dialog.dart';
import '../auth/sign_out.dart';
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
      appBar: AppBar(
        title: const Text('Seasons'),
        actions: const [_ShellMenu()],
      ),
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

/// App-shell overflow menu (task 4.1): authenticated identity, About,
/// Settings, Sign out. Lives on the seasons screen until Phase 1b adds a
/// dedicated shell.
///
/// About opens the info dialog (task 5.1); Settings opens the settings
/// dialog (task 6.4). Sign out runs the full [SessionReset] coordinator
/// (never throws — failures surface as gate state).
class _ShellMenu extends ConsumerWidget {
  const _ShellMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    final sub = switch (session) {
      AsyncData(:final value) => value?.sub ?? '',
      _ => '',
    };
    return PopupMenuButton<_ShellMenuItem>(
      key: const Key('seasons-menu-button'),
      icon: const Icon(Icons.more_vert),
      tooltip: 'Account and app options',
      onSelected: (item) async {
        switch (item) {
          case _ShellMenuItem.about:
            if (context.mounted) await showAppInfoDialog(context);
          case _ShellMenuItem.settings:
            if (context.mounted) await showSettingsDialog(context);
          case _ShellMenuItem.signOut:
            await ref.read(sessionResetProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_ShellMenuItem>(
          enabled: false,
          child: ListTile(
            key: const Key('menu-identity'),
            leading: const Icon(Icons.account_circle),
            title: Text(sub.isEmpty ? 'Signed out' : sub),
            subtitle: const Text('Signed in'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_ShellMenuItem>(
          key: Key('menu-about'),
          value: _ShellMenuItem.about,
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
          ),
        ),
        const PopupMenuItem<_ShellMenuItem>(
          key: Key('menu-settings'),
          value: _ShellMenuItem.settings,
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_ShellMenuItem>(
          key: Key('menu-signout'),
          value: _ShellMenuItem.signOut,
          child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out')),
        ),
      ],
    );
  }
}

enum _ShellMenuItem { about, settings, signOut }

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
