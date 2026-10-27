// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';

/// The profile affordance (issues #610/#613, relocated in #638, now the
/// account-drawer trigger in #653): the minimal home the dissolved `Mehr`
/// destination needed when the shell moved to three task views.
///
/// Placement (issue #638): the LEFT-MOST element of the shell's sticky top
/// bar (row 1), ahead of the scope pills — one affordance for the whole
/// shell, never one per destination root.
///
/// Behavior (issue #653): tapping opens the user ACCOUNT DRAWER — a
/// Material 3 `NavigationDrawer` hosted as the shell `Scaffold`'s side
/// drawer, sliding in as an overlay above the content (with scrim),
/// Spotify-style. It is deliberately NOT a bottom sheet (nothing slides
/// up from the bottom) and NOT a dialog. The drawer's entries (identity,
/// *Über die App*, *Einstellungen*, *Abmelden*) live in
/// `AccountDrawer`; this widget is only the trigger.
///
/// Note what is NOT here: the piece-category vocabulary. Categories are
/// piece-domain content and live with the Cast view (hard acceptance
/// criterion of issue #610, cross-confirmed by #613).
///
/// // AUTHZ-GATE: the drawer is `Authenticated`-gated UI that is only
/// reachable from inside the shell (below `AuthGate`); this trigger
/// dispatches no command itself — it only opens the shell drawer.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return IconButton(
      key: const Key('profile-menu-button'),
      icon: const Icon(BreakdownMaterialIcons.shellProfile),
      tooltip: l10n.profileTooltip,
      // The drawer is hosted by the shell Scaffold (all three
      // morphologies), so this body context always has a Scaffold
      // ancestor. Opening is fire-and-forget (no result consumed).
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}
