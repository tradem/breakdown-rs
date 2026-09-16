// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/seasons_cache_providers.dart';
import '../blocks/blocks_screen.dart';
import 'shell_controller.dart';

/// The Planen tab root (task 4.1): the hierarchy entry.
///
/// Lists the seasons of the active series (same repository-backed
/// projection as the Season tab); tapping a season sets the shell's
/// active season from the acted-on DTO (CQRS boundary — never a second
/// projection lookup) and pushes `BlocksScreen` on THIS tab's nested
/// navigator (design D4: the screens themselves are unchanged; only the
/// pushing context moves). Further drill-down (blocks → episodes →
/// scenes) keeps pushing on this tab's navigator.
///
/// Back/Up inside the drill-down pops within this tab (shell back
/// behavior, D3).
class PlanningTabScreen extends ConsumerWidget {
  const PlanningTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(seasonsView);
    final rows = view.rows;

    return Scaffold(
      appBar: AppBar(title: const Text('Planen')),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: Builder(
          builder: (context) {
            if (rows.isEmpty) {
              return ListView(
                key: const Key('planen-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 160),
                  Center(
                    child: view.error != null
                        ? Text(
                            'Seasons could not be loaded '
                            '(${view.error!.code}).',
                          )
                        : const Text('No seasons yet'),
                  ),
                ],
              );
            }
            return ListView.builder(
              key: const Key('planen-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final season = rows[i];
                return ListTile(
                  key: Key('planen-season-${season.id}'),
                  title: Text(season.title ?? 'Season ${season.number}'),
                  subtitle: Text('Number ${season.number}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openSeason(context, ref, season),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Sets the active season from the tapped DTO (design D5: last-opened
  /// season) and pushes BlocksScreen on the Planen tab's nested navigator.
  void _openSeason(BuildContext context, WidgetRef ref, SeasonView season) {
    ref.read(shellControllerProvider.notifier).setActiveSeason(season);
    // Fire-and-forget navigation (no result consumed).
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BlocksScreen(season: season)),
      ),
    );
  }

  /// Pull-to-refresh: re-runs the seasons projection fetch seam (writes
  /// Drift on success, never on failure — the `add-drift-read-cache`
  /// contract), mirroring the refetch boundary the controller uses.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(seasonsListFetchProvider);
    ref.invalidate(seasonsCacheStaleProvider);
    ref.invalidate(seasonsViewControllerProvider);
    final res = await ref.read(seasonsListFetchProvider.future);
    // The fetch seam writes Drift on Right and leaves it untouched on
    // Left (the view surfaces the error); the refresh future itself only
    // bounds the pull-to-refresh spinner.
    res.fold((_) {}, (_) {});
  }
}
