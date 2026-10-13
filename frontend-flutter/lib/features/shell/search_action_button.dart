// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../omni_search/omni_search_screen.dart';

/// The shell's top-bar search affordance (issues #613/#616, task 4.1).
///
/// Placement (issue #638): the SECOND row of the shell's sticky top bar,
/// trailing the view title and the hierarchy breadcrumb — the #613 slot
/// ("profile/settings … with the OmniSearch entry beside it") is now
/// shell-owned, so the entry is persistent from anywhere inside the shell in
/// all three morphologies (compact bottom navigation, medium rail, expanded
/// drawer). It is never a bottom-bar destination tab.
///
/// The push targets the ACTIVE DESTINATION's navigator: the shell passes the
/// active tab's `GlobalKey<NavigatorState>` as [navigatorKey], so the
/// surface opens inside the active view's stack (back returns there) — the
/// same target the affordance had when it lived on the destination app bar.
/// A `null` [navigatorKey] falls back to `Navigator.of(context)`.
///
/// // AUTHZ-GATE: the surface is `Authenticated`-gated UI reached only
/// from inside the shell (below `AuthGate`); the search itself issues no
/// network call (data-only over the client cache), so this affordance
/// dispatches no command and needs no membership check beyond the shell
/// gate.
class ShellSearchAction extends ConsumerWidget {
  const ShellSearchAction({super.key, this.navigatorKey});

  /// The active destination's nested navigator (issue #638). Resolved at tap
  /// time — the key's state is not guaranteed during the first build.
  final GlobalKey<NavigatorState>? navigatorKey;

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
    final navigator = navigatorKey?.currentState ?? Navigator.of(context);
    // Fire-and-forget navigation (no result consumed — `unawaited` marks
    // the discard explicitly per the breakdown_lints `discard_result` rule).
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const OmniSearchScreen()),
      ),
    );
  }
}
