// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';
import '../app_info/info_dialog.dart';
import '../auth/sign_out.dart';
import '../settings/settings_screen.dart';

/// The profile affordance (issues #610/#613, relocated in #638): the
/// minimal home the dissolved `Mehr` destination needed when the shell moved
/// to three task views.
///
/// Placement (issue #638): the LEFT-MOST element of the shell's sticky top
/// bar (row 1), ahead of the scope pills — one affordance for the whole
/// shell, never one per destination root. It is deliberately small —
/// identity, *Über die App*, *Einstellungen*, *Abmelden* — because the
/// final top-bar design belongs to issue #638, which owns this slot.
///
/// The settings push targets the ACTIVE DESTINATION's navigator: the shell
/// passes the active tab's `GlobalKey<NavigatorState>` as [navigatorKey], so
/// the screen opens inside the active view's stack — the same target the
/// affordance had when it lived on the destination app bar. A `null`
/// [navigatorKey] falls back to `Navigator.of(context)`.
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
  const ProfileMenuButton({super.key, this.navigatorKey});

  /// The active destination's nested navigator (issue #638). Resolved at tap
  /// time — the key's state is not guaranteed during the first build.
  final GlobalKey<NavigatorState>? navigatorKey;

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
    // `ref.read`, not `ref.watch`: this runs from the tap handler, OUTSIDE
    // the build phase — watching there is invalid and newer Riverpod
    // versions assert on it. The sheet shows the identity as it is at open
    // time; a session change tears the shell down anyway.
    final session = ref.read(authSessionControllerProvider);
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
                  final navigator =
                      navigatorKey?.currentState ?? Navigator.of(context);
                  // Fire-and-forget navigation (no result consumed).
                  unawaited(
                    navigator.push(
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
