// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import '../app_info/app_info_screen.dart';
import '../auth/sign_out.dart';
import '../settings/settings_screen.dart';

/// The user account drawer (issue #653): a Material 3
/// [NavigationDrawer] hosted as the shell Scaffolds' side drawer —
/// Spotify-style: it slides in FROM THE SIDE as an overlay above the
/// content (scrim included) when the top bar's user icon taps
/// `Scaffold.of(context).openDrawer()`. It is never a bottom sheet and
/// nothing slides up from the bottom; tap-outside and swipe dismiss are
/// Material's own drawer gestures.
///
/// Hosting: the drawer is mounted on the shell Scaffolds (all three
/// morphologies), so it sits on the ROOT navigator — its scrim covers the
/// whole shell including the top bar, and a destination switch cannot
/// strand it in an `IndexedStack` navigator as an invisible route.
///
/// Entries: the signed-in identity header, *Über die App* (→ pushes the
/// FULL SCREEN [AppInfoScreen] — explicitly not a dialog), *Einstellungen*
/// (→ pushes the full-screen [SettingsScreen]) and *Abmelden* (→ the
/// OIDC/session-reset sign-out flow). Pushes target the ACTIVE
/// destination's nested navigator ([navigatorKey], issue #638's D7 seam) —
/// the screens open inside the active view's stack so back returns to the
/// destination, not out of the shell.
///
/// // AUTHZ-GATE: the drawer is `Authenticated`-gated UI that only exists
/// inside the shell; it dispatches no command itself beyond the session
/// reset. No membership check of its own is needed (same rule as the
/// former profile sheet).
class AccountDrawer extends ConsumerWidget {
  const AccountDrawer({super.key, this.navigatorKey});

  /// The active destination's nested navigator (issue #638): the push
  /// target for the About and Settings screens. The key's state is not
  /// guaranteed during the first build — reads happen at tap time.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    // The drawer is always mounted (Scaffold slot), so watching the
    // session here is safe and keeps the identity current while open.
    // A session change tears the shell down anyway.
    final session = ref.watch(authSessionControllerProvider);
    final sub = switch (session) {
      AsyncData(:final value) => value?.sub ?? '',
      _ => '',
    };
    return NavigationDrawer(
      key: const Key('profile-account-drawer'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
          child: ListTile(
            key: const Key('profile-identity'),
            enabled: false,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle),
            title: Text(sub.isEmpty ? l10n.commonSignedOut : sub),
            subtitle: Text(l10n.commonSignedIn),
          ),
        ),
        const Divider(),
        ListTile(
          key: const Key('profile-about'),
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.commonAbout),
          onTap: () {
            // Issue #653: About is a FULL SCREEN route — never a dialog.
            // The helper captures the destination navigator BEFORE the
            // pop (see showAppInfoScreen), so closing the drawer first is
            // safe — single push path, same seam as Settings below.
            Navigator.of(context).pop();
            showAppInfoScreen(context, navigatorKey: navigatorKey);
          },
        ),
        ListTile(
          key: const Key('profile-settings'),
          leading: const Icon(Icons.settings_outlined),
          // Issue #516: full-screen settings (no dialog) — app-bar back
          // navigation; opened inside the ACTIVE destination's stack.
          title: Text(l10n.commonSettings),
          onTap: () {
            final navigator = navigatorKey?.currentState;
            Navigator.of(context).pop();
            if (navigator != null) {
              unawaited(
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              );
            }
          },
        ),
        ListTile(
          key: const Key('profile-signout'),
          leading: const Icon(Icons.logout),
          title: Text(l10n.commonSignOut),
          onTap: () {
            Navigator.of(context).pop();
            unawaited(ref.read(sessionResetProvider.notifier).signOut());
          },
        ),
      ],
    );
  }
}
