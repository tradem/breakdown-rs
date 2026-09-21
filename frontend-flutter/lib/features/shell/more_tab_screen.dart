// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../app_info/info_dialog.dart';
import '../app_info/settings_dialog.dart';
import '../auth/sign_out.dart';
import '../costume_categories/costume_categories_screen.dart';
import 'shell_controller.dart';

/// The Mehr tab root (task 4.3): secondary destinations as labeled list
/// entries — costume categories (active-season scoped), About, Settings,
/// Sign out.
///
/// The AI-import entry lives in the Planen tab (the import creates
/// planning entities — season/block/episode/schedule — so its action
/// sits where that structure is built). Reports are intentionally NOT
/// listed here (design D8: `ReportsScreen` is strictly day-scoped;
/// reports stay anchored in the day board).
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
          ListTile(
            key: const Key('mehr-categories-entry'),
            leading: const Icon(Icons.style_outlined),
            title: const Text('Kostüm-Kategorien'),
            subtitle: season == null
                // CodeRabbit review fix: name the tab that CAN set the
                // active season (Planen — from the acted-on season row
                // DTO); the entry itself jumps there when disabled.
                ? const Text('Season im Planen-Tab öffnen')
                : Text(season.title ?? 'Season ${season.number}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: season == null
                ? () => ref
                      .read(shellControllerProvider.notifier)
                      .selectTab(kPlanenTabIndex)
                : () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CostumeCategoriesScreen(season: season),
                      ),
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
