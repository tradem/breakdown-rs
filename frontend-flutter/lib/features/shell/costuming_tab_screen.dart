// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../characters/characters_screen.dart';
import '../costumes/costumes_screen.dart';
import 'shell_controller.dart';

/// The Kleidung tab root (task 4.2): the costume department's tab, scoped
/// to the shell's active season.
///
/// - With an active season: labeled entries into the season-scoped
///   `CostumesScreen` and `CharactersScreen` (their controllers, keys,
///   repositories and AUTHZ-GATE comments are unchanged — only the entry
///   point moves, design D4). Both push on this tab's nested navigator.
/// - Without an active season: a season-selection empty state with a CTA
///   jumping to the **Planen tab** (spec scenario "No active season" —
///   never an error). The Planen tab is the surface that SETS the active
///   season (from the acted-on season row DTO, D5); the Season tab is a
///   pure overview whose rows do not navigate, so the CTA points there.
///
/// The active season is consumed as plain data from
/// `ShellState.activeSeason` (D5) — the widgets carry no season-changing
/// token knowledge.
class CostumingTabScreen extends ConsumerWidget {
  const CostumingTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(title: const Text('Kleidung')),
      body: season == null
          ? ListView(
              key: const Key('kleidung-empty'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                const Icon(Icons.checkroom_outlined, size: 48),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Wähle eine Season im Planen-Tab, um Kostüme '
                    'und Figuren zu sehen.',
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton(
                    key: const Key('kleidung-select-season-cta'),
                    onPressed: () => ref
                        .read(shellControllerProvider.notifier)
                        .selectTab(kPlanenTabIndex),
                    child: const Text('Season im Planen-Tab wählen'),
                  ),
                ),
              ],
            )
          : ListView(
              key: const Key('kleidung-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ListTile(
                  key: const Key('kleidung-costumes-entry'),
                  leading: const Icon(Icons.checkroom_outlined),
                  title: const Text('Kostüme'),
                  subtitle: Text(season.title ?? 'Season ${season.number}'),
                  trailing: const Icon(Icons.chevron_right),
                  // Fire-and-forget navigation (no result consumed).
                  onTap: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CostumesScreen(season: season),
                      ),
                    ),
                  ),
                ),
                ListTile(
                  key: const Key('kleidung-characters-entry'),
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Figuren'),
                  subtitle: Text(season.title ?? 'Season ${season.number}'),
                  trailing: const Icon(Icons.chevron_right),
                  // Fire-and-forget navigation (no result consumed).
                  onTap: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CharactersScreen(season: season),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
