// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../app_info/info_dialog.dart';
import '../app_info/settings_dialog.dart';
import '../ai_import/import_jobs/import_submit_screen.dart';
import '../auth/sign_out.dart';
import '../costume_categories/costume_categories_screen.dart';
import 'shell_controller.dart';

/// The Mehr tab root (task 4.3): secondary destinations as labeled list
/// entries — AI import, costume categories (active-season scoped),
/// About, Settings, Sign out.
///
/// The AI-import entry's AUTHZ-GATE comment travels with it (the submit
/// controller gates BEFORE any network call — `grep AUTHZ-GATE` stays
/// green). Reports are intentionally NOT listed here (design D8:
/// `ReportsScreen` is strictly day-scoped; reports stay anchored in the
/// day board).
///
/// Secondary entries push on this tab's nested navigator; dialogs stay
/// dialogs. Sign-out runs the [SessionReset] coordinator (never throws —
/// failures surface as gate state, the shell disappears with the
/// session).
class MoreTabScreen extends ConsumerWidget {
  const MoreTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(title: const Text('Mehr')),
      body: ListView(
        key: const Key('mehr-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Authenticated identity (key contract carried over from the
          // seasons overflow menu): non-interactive, key for tests.
          Builder(
            builder: (context) {
              final session = ref.watch(authSessionControllerProvider);
              final sub = switch (session) {
                AsyncData(:final value) => value?.sub ?? '',
                _ => '',
              };
              return ListTile(
                key: const Key('menu-identity'),
                enabled: false,
                leading: const Icon(Icons.account_circle),
                title: Text(sub.isEmpty ? 'Signed out' : sub),
                subtitle: const Text('Signed in'),
              );
            },
          ),
          const Divider(),
          // AUTHZ-GATE: the AI-import upload routes are gated by the season
          // costume-dept membership; the gate runs inside the submit
          // controller BEFORE any network call (the entry action itself is
          // auth-only — the screens render the denial narratives). This
          // comment moved with the entry from the seasons AppBar (task 4.3).
          ListTile(
            key: const Key('mehr-ai-import'),
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Import'),
            subtitle: const Text('KI-Assistent: Spielplan importieren'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AiImportSubmitScreen(),
              ),
            ),
          ),
          ListTile(
            key: const Key('mehr-categories-entry'),
            leading: const Icon(Icons.style_outlined),
            title: const Text('Kategorien'),
            subtitle: season == null
                ? const Text('First select a season')
                : Text(season.title ?? 'Season ${season.number}'),
            enabled: season != null,
            trailing: const Icon(Icons.chevron_right),
            onTap: season == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CostumeCategoriesScreen(season: season),
                    ),
                  ),
          ),
          const Divider(),
          ListTile(
            key: const Key('mehr-about'),
            leading: const Icon(Icons.info_outline),
            title: const Text('Über die App'),
            onTap: () => showAppInfoDialog(context),
          ),
          ListTile(
            key: const Key('mehr-settings'),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Einstellungen'),
            onTap: () => showSettingsDialog(context),
          ),
          ListTile(
            key: const Key('mehr-signout'),
            leading: const Icon(Icons.logout),
            title: const Text('Abmelden'),
            onTap: () async {
              await ref.read(sessionResetProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }
}
