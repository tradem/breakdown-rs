// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations_provider.dart';

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
    final l10n = l10nOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.seasonsEmptyTitle,
              key: const Key('seasons-empty-title'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.seasonsEmptyGuidance,
              key: const Key('seasons-empty-guidance'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('seasons-empty-setup-cta'),
              onPressed: onSetup,
              icon: const Icon(Icons.add),
              label: Text(l10n.seasonsEmptySetupCta),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('seasons-empty-import-cta'),
              onPressed: onImport,
              icon: const Icon(Icons.smart_toy_outlined),
              label: Text(l10n.seasonsEmptyImportCta),
            ),
          ],
        ),
      ),
    );
  }
}
