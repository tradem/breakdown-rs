// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

/// Guided empty state of the Season tab (`redesign-seasons-home` task 3.4):
/// headline + one sentence of guidance + two CTAs —
/// * setup (gated by the session, like the FAB — `onSetup` is `null` when
///   the create flow is unavailable);
/// * import (jumps to the Mehr tab's AI-import entry — a pure client
///   navigation; the membership AUTHZ-GATE runs inside the import submit
///   controller BEFORE any network call).
///
/// Pure presentation: callbacks in, copy from the glossary
/// (`seasons.empty.title` / `seasons.empty.guidance` /
/// `seasons.empty.setupCta` / `seasons.empty.importCta`).
class SeasonsEmptyState extends StatelessWidget {
  const SeasonsEmptyState({super.key, required this.onImport, this.onSetup});

  /// Season-setup entry (existing create flow; later the setup wizard's
  /// route). `null` disables the CTA (session gate — same rule as the FAB).
  final VoidCallback? onSetup;

  /// Switches to the Mehr tab (import entry).
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'Noch keine Seasons',
              key: const Key('seasons-empty-title'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Lege deine erste Season an — oder importiere einen '
              'bestehenden Spielplan per KI.',
              key: const Key('seasons-empty-guidance'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('seasons-empty-setup-cta'),
              onPressed: onSetup,
              icon: const Icon(Icons.add),
              label: const Text('Season-Setup starten'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('seasons-empty-import-cta'),
              onPressed: onImport,
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('KI-Import öffnen'),
            ),
          ],
        ),
      ),
    );
  }
}
