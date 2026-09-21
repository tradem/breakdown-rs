// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/seasons_cache_providers.dart';
import '../ai_import/import_jobs/import_submit_screen.dart';
import '../blocks/blocks_screen.dart';
import 'shell_controller.dart';

/// The AI-import entry's AUTHZ-GATE comment travels with it (the submit
/// controller gates BEFORE any network call — `grep AUTHZ-GATE` stays
/// green). The entry moved here from the Mehr tab: the import creates
/// planning entities (season/block/episode/schedule) for the seasons
/// managed in this tab.

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
            final importEntry = _aiImportEntry(context);
            if (rows.isEmpty) {
              return ListView(
                key: const Key('planen-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  importEntry,
                  const SizedBox(height: 120),
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
              // Index 0 is the AI-import entry; 1..n are the season rows.
              itemCount: rows.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return importEntry;
                final season = rows[i - 1];
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

  /// The AI-import entry (moved from the Mehr tab): the KI-assistant
  /// creates planning entities for a season, so its action lives here.
  ListTile _aiImportEntry(BuildContext context) {
    return ListTile(
      key: const Key('planen-ai-import'),
      leading: const Icon(Icons.smart_toy_outlined),
      title: const Text('Import'),
      subtitle: const Text('KI-Assistent: Spielplan importieren'),
      trailing: const Icon(Icons.chevron_right),
      // Fire-and-forget navigation (no result consumed).
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AiImportSubmitScreen()),
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
