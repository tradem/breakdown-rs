// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';
import '../app_info/info_dialog.dart';
import '../auth/sign_out.dart';
import '../settings/settings_screen.dart';

/// The profile affordance (issue #610): the minimal home the dissolved
/// `Mehr` destination needed when the shell moved to three task views.
///
/// It is deliberately small — identity, *Über die App*, *Einstellungen*,
/// *Abmelden* — because issue #613 owns the final top-bar design (and the
/// OmniSearch entry beside it). It is mounted on all three destination
/// roots so the entries are reachable from anywhere without giving the
/// settings surface back its status as a navigation destination.
///
/// Note what is NOT here: the costume-category vocabulary. Categories are
/// costume-domain content and live with the Cast view (hard acceptance
/// criterion of issue #610, cross-confirmed by #613).
///
/// // AUTHZ-GATE: sign-out runs the `SessionReset` coordinator; the settings
/// and info surfaces are `Authenticated`-gated UI that is only reachable
/// from inside the shell. No command is dispatched from this widget itself
/// beyond the session reset.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return IconButton(
      key: const Key('profile-menu-button'),
      icon: const Icon(BreakdownMaterialIcons.shellProfile),
      tooltip: l10n.profileTooltip,
      onPressed: () => _open(context, ref),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final session = ref.watch(authSessionControllerProvider);
    final sub = switch (session) {
      AsyncData(:final value) => value?.sub ?? '',
      _ => '',
    };
    // Fire-and-forget menu presentation (no result consumed).
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('profile-identity'),
                enabled: false,
                leading: const Icon(Icons.account_circle),
                title: Text(sub.isEmpty ? l10n.commonSignedOut : sub),
                subtitle: Text(l10n.commonSignedIn),
              ),
              const Divider(),
              ListTile(
                key: const Key('profile-about'),
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.commonAbout),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showAppInfoDialog(context);
                },
              ),
              ListTile(
                key: const Key('profile-settings'),
                leading: const Icon(Icons.settings_outlined),
                // Issue #516: full-screen settings (no dialog) — app-bar
                // back navigation, general vs. development separation.
                title: Text(l10n.commonSettings),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  // Fire-and-forget navigation (no result consumed).
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                key: const Key('profile-signout'),
                leading: const Icon(Icons.logout),
                title: Text(l10n.commonSignOut),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(ref.read(sessionResetProvider.notifier).signOut());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
