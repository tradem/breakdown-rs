// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../omni_search/omni_search_screen.dart';

/// The shell's top-bar search affordance (issues #613/#616, task 4.1).
///
/// Placed BESIDE the profile action on every destination root's app bar
/// (the #613 top-bar slot: "profile/settings … with the OmniSearch entry
/// beside it") — mounted on all three destination screens so the entry is
/// persistent from anywhere inside the shell in BOTH morphologies (the app
/// bar renders under the compact bottom-[NavigationBar] and the wide
/// [NavigationRail] alike). It is never a bottom-bar destination tab.
///
/// The push targets the DESTINATION navigator the app bar already lives
/// in (`Navigator.of(context)` from within the tab content) — the surface
/// opens inside the active view's stack (back returns there), no shell
/// GlobalKey wiring and no parallel route system.
///
/// // AUTHZ-GATE: the surface is `Authenticated`-gated UI reached only
/// from inside the shell (below `AuthGate`); the search itself issues no
/// network call (data-only over the client cache), so this affordance
/// dispatches no command and needs no membership check beyond the shell
/// gate.
class ShellSearchAction extends ConsumerWidget {
  const ShellSearchAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: const Key('shell-search-action'),
      tooltip: l10nOf(context).omniSearchTooltip,
      onPressed: () => _open(context),
      icon: const Icon(Icons.search),
    );
  }

  void _open(BuildContext context) {
    // Fire-and-forget navigation (no result consumed — `unawaited` marks
    // the discard explicitly per the breakdown_lints `discard_result` rule,
    // the same shape `ProfileMenuButton` uses).
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const OmniSearchScreen())),
    );
  }
}
