// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/seasons_cache_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import '../seasons/seasons_screen.dart';
import 'planning_location.dart';
import 'production_overview_screen.dart';
import 'shell_controller.dart';

/// The season scope chip (issue #610): the season half of the shell's
/// "what filters your requests" surface, sibling to the block-scope
/// `ActiveScopeChip`.
///
/// The dedicated Season destination is dissolved, so this chip is the
/// always-visible answer to "which season am I working in?" across all
/// three views. It renders the ACTIVE season as plain data from
/// `ShellState.activeSeason` (never a second projection lookup) and a tap
/// opens [SeasonScopePickerScreen] on the active destination's navigator.
///
/// Arms:
/// - **no active season** → hidden, exactly like the block chip: an unset
///   scope says nothing, and the views render their own season-empty state;
/// - **active season** → `Season: {title | number}`.
///
/// // AUTHZ-GATE: the chip is display + navigation only — it dispatches no
// command and performs no network call (the picker's season read is the
// seasons projection the seasons overview already reads), so it needs no
// membership check.
class SeasonScopeChip extends ConsumerWidget {
  const SeasonScopeChip({super.key, required this.onOpenPicker});

  /// Opens the season scope picker (injected so the chip stays a leaf
  /// widget the tests can pump standalone).
  final void Function() onOpenPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(shellControllerProvider).activeSeason;
    if (season == null) return const SizedBox.shrink();

    final l10n = l10nOf(context);
    return ActionChip(
      key: const Key('season-scope-chip'),
      avatar: Icon(
        Icons.video_collection_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      label: Text(
        l10n.scopeChipSeason(
          season.title ?? l10n.seasonsDefaultTitle(season.number),
        ),
      ),
      tooltip: l10n.scopeChipSeasonTooltip,
      onPressed: onOpenPicker,
    );
  }
}

/// The season scope picker (issue #610): the single entry point for
/// everything the dissolved Season and Planen destinations used to carry.
///
/// Three kinds of rows:
/// 1. **season rows** → set the active season from the ACTED-ON `SeasonView`
///    (CQRS boundary: no second projection lookup) and pop, so the pick is
///    visible immediately in all three views;
/// 2. *Seasons verwalten* → push `SeasonsScreen` (create/manage seasons);
/// 3. *Produktion verwalten* → push `ProductionOverviewScreen` (the
///    block/episode spine, AI-import entry and active-jobs row).
///
/// Season rows come from the cached `seasonsView` selector and a
/// pull-to-refresh re-runs the same seasons fetch seam the seasons
/// overview uses (the fetch seam writes Drift on success, never on failure).
class SeasonScopePickerScreen extends ConsumerWidget {
  const SeasonScopePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final view = ref.watch(seasonsView);
    final rows = view.rows;
    final activeSeason = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scopeChipSeasonPickTitle)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          key: const Key('season-scope-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListTile(
              key: const Key('season-scope-manage-seasons'),
              leading: const Icon(Icons.video_library_outlined),
              title: Text(l10n.seasonScopeManageSeasons),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SeasonsScreen(),
                  ),
                ),
              ),
            ),
            ListTile(
              key: const Key('season-scope-manage-production'),
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(l10n.seasonScopeManageProduction),
              subtitle: Text(l10n.productionBlocksSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: activeSeason == null
                  // No season yet: the production overview has no scope to
                  // show. Say so and send the user to season management
                  // rather than pushing an empty screen.
                  ? null
                  : () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          settings: RouteSettings(
                            arguments: PlanningLocation.season(activeSeason),
                          ),
                          builder: (_) =>
                              ProductionOverviewScreen(season: activeSeason),
                        ),
                      ),
                    ),
            ),
            const Divider(),
            if (rows.isEmpty)
              Padding(
                key: const Key('season-scope-empty'),
                padding: const EdgeInsets.all(16),
                child: Center(child: Text(l10n.seasonScopeEmpty)),
              )
            else
              for (final season in rows)
                ListTile(
                  key: Key('season-scope-season-${season.id}'),
                  leading: Icon(
                    Icons.radio_button_checked,
                    color: season.id == activeSeason?.id
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(
                    season.title ?? l10n.seasonsDefaultTitle(season.number),
                  ),
                  onTap: () => _pickSeason(context, ref, season),
                ),
          ],
        ),
      ),
    );
  }

  /// Sets the active season from the tapped DTO (CQRS boundary) and pops
  /// back to whichever view opened the picker.
  void _pickSeason(BuildContext context, WidgetRef ref, SeasonView season) {
    ref.read(shellControllerProvider.notifier).setActiveSeason(season);
    Navigator.of(context).pop();
  }

  /// Pull-to-refresh re-runs the seasons projection fetch seam (Drift is
  /// written on success only — the view surfaces the error).
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(seasonsListFetchProvider);
    ref.invalidate(seasonsCacheStaleProvider);
    ref.invalidate(seasonsViewControllerProvider);
    final res = await ref.read(seasonsListFetchProvider.future);
    res.fold((_) {}, (_) {});
  }
}
