// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: space-bunny-free (opencode)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/seasons_cache_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import 'widgets/season_card.dart';

/// Localized, client-side copy keyed on the stable problem `code` (AGENTS.md
/// §5). Network failures disable writes with an "online required" message
/// (Task 4.2). The narratives live in the ARB catalogs
/// (`seasonsOnlineRequired`, `seasonsStaleBanner`, `seasonsErrorBanner`).

/// Seasons screen bound to the cache-backed [seasonsView] projection.
///
/// Renders only from the projection: never reads the API client or the cache
/// directly (Design Decision D1). Shows a stale indicator when the served rows
/// are from an expired cache or a failed refetch (D2/D4), and disables the
/// write FAB while offline (last fetch failed, Task 4.2).
///
/// Presentation follows the seasons-home capability (task 3.2): rows render
/// as Material 3 cards instead of tiles (no cached metadata source on this
/// standalone projection — cards render title + chevron only).
class SeasonsViewWidget extends ConsumerWidget {
  const SeasonsViewWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(seasonsView);

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).seasonsTitle)),
      // 4.2: write actions are disabled while offline (last fetch failed).
      floatingActionButton: FloatingActionButton(
        key: const Key('season-add-fab'),
        onPressed: view.error != null
            ? null
            : () {
                // Wired by first-screen-seasons; placeholder here.
              },
        tooltip: view.error != null
            ? l10nOf(context).seasonsOnlineRequired
            : l10nOf(context).seasonsAddTooltip,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (view.isStale)
            _Banner(
              key: const Key('stale-banner'),
              text: l10nOf(context).seasonsStaleBanner,
              color: Colors.orange,
            ),
          if (view.error != null)
            _Banner(
              key: const Key('error-banner'),
              text: l10nOf(context).seasonsErrorBanner,
              color: Colors.red,
              action: TextButton(
                key: const Key('retry-button'),
                onPressed: () {
                  ref.invalidate(seasonsListFetchProvider);
                  ref.invalidate(seasonsViewControllerProvider);
                },
                child: Text(l10nOf(context).commonRetry),
              ),
            ),
          Expanded(
            child: view.rows.isEmpty
                ? Center(child: Text(l10nOf(context).seasonsEmpty))
                : ListView.builder(
                    itemCount: view.rows.length,
                    itemBuilder: (context, i) {
                      final s = view.rows[i];
                      return SeasonCard(
                        key: Key('season-${s.id}'),
                        title:
                            s.title ??
                            l10nOf(context).wizardReviewSeason('${s.number}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.color,
    this.action,
  });

  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    color: color.withValues(alpha: 0.15),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(text)),
        // ignore: use_null_aware_elements
        if (action != null) action!,
      ],
    ),
  );
}
