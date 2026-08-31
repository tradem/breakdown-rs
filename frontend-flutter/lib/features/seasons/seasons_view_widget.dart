// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/seasons_cache_providers.dart';

/// Localized, client-side copy keyed on the stable problem `code` (AGENTS.md
/// §5). Network failures disable writes with an "online required" message
/// (Task 4.2).
const String _onlineRequired = 'Online connection required';
const String _staleBanner = 'Cached data may be outdated';
const String _errorBanner = 'Couldn’t refresh — showing cached data';

/// Seasons screen bound to the cache-backed [seasonsView] projection.
///
/// Renders only from the projection: never reads the API client or the cache
/// directly (Design Decision D1). Shows a stale indicator when the served rows
/// are from an expired cache or a failed refetch (D2/D4), and disables the
/// write FAB while offline (last fetch failed, Task 4.2).
class SeasonsViewWidget extends ConsumerWidget {
  const SeasonsViewWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(seasonsView);

    return Scaffold(
      appBar: AppBar(title: const Text('Seasons')),
      // 4.2: write actions are disabled while offline (last fetch failed).
      floatingActionButton: FloatingActionButton(
        key: const Key('season-add-fab'),
        onPressed: view.error != null
            ? null
            : () {
                // Wired by first-screen-seasons; placeholder here.
              },
        tooltip: view.error != null ? _onlineRequired : 'Add season',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (view.isStale)
            const _Banner(
              key: Key('stale-banner'),
              text: _staleBanner,
              color: Colors.orange,
            ),
          if (view.error != null)
            _Banner(
              key: const Key('error-banner'),
              text: _errorBanner,
              color: Colors.red,
              action: TextButton(
                key: Key('retry-button'),
                onPressed: () {
                  ref.invalidate(seasonsListFetchProvider);
                  ref.invalidate(seasonsViewControllerProvider);
                },
                child: const Text('Retry'),
              ),
            ),
          Expanded(
            child: view.rows.isEmpty
                ? const Center(child: Text('No seasons yet'))
                : ListView.builder(
                    itemCount: view.rows.length,
                    itemBuilder: (context, i) {
                      final s = view.rows[i];
                      return ListTile(
                        key: Key('season-${s.id}'),
                        title: Text(s.title ?? 'Season ${s.number}'),
                        subtitle: Text('Number ${s.number}'),
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
