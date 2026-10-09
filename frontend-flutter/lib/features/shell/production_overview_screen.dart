// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../ai_import/import_jobs/import_submit_screen.dart';
import '../ai_import/import_jobs/jobs_controller.dart';
import '../ai_import/import_jobs/jobs_screen.dart';
import '../blocks/blocks_controller.dart';
import '../blocks/blocks_screen.dart';
import 'planning_location.dart';

/// The production overview (issue #610) — what the former `Planen`
/// destination carried, re-homed as a PUSHED screen reachable from the
/// season scope picker's *Produktion verwalten* entry.
///
/// It is the management surface of the active season's production
/// structure (blocks → episodes → scenes) plus the two entries that create
/// that structure: the AI import and its active-jobs row. Season *listing*
/// is no longer here — seasons are picked and managed from the scope chip
/// (one surface, all three views).
///
/// The AI-import entry's AUTHZ-GATE comment travels with it (the submit
/// controller gates BEFORE any network call — `grep AUTHZ-GATE` stays
/// green). The entry lives here because the import creates planning
/// entities (season/block/episode/schedule) for exactly this season.
class ProductionOverviewScreen extends ConsumerWidget {
  const ProductionOverviewScreen({super.key, required this.season});

  /// The season this overview manages — the shell's active season, handed
  /// down as plain data by the scope picker (never re-resolved here).
  final SeasonView season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.productionTitle)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          key: const Key('production-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListTile(
              key: const Key('production-season-row'),
              leading: const Icon(Icons.video_collection_outlined),
              title: Text(
                season.title ?? l10n.seasonsDefaultTitle(season.number),
              ),
              subtitle: Text(l10n.productionBlocksSubtitle),
            ),
            _activeJobsRow(context, ref),
            _aiImportEntry(context),
            ListTile(
              key: const Key('production-blocks-entry'),
              leading: const Icon(Icons.folder_outlined),
              title: Text(l10n.navBlocks),
              subtitle: Text(l10n.productionBlocksSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openBlocks(context, season),
            ),
          ],
        ),
      ),
    );
  }

  /// The active-jobs summary row (issue #547): visible while at least one
  /// known AI-import job needs attention (any non-`succeeded` status — a
  /// silent `dead_letter` keeps summoning the row until it is replaced).
  /// It READS the `aiImportJobsView` cached state and pushes the jobs
  /// screen; it arms NO watch (the single foreground watch stays owned by
  /// `AiJobStatusScreen`) and dispatches nothing.
  ///
  /// // AUTHZ-GATE: this row is a navigation target only — the jobs list
  /// route is ownership-scoped server-side and its fetch seam resolves
  /// the session before the call (see `aiImportJobsFetch`); the
  /// block-scope gate of the AI-import submit entry below is unchanged.
  Widget _activeJobsRow(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(aiImportJobsView);
    final attention = jobs.rows.where((job) => job.needsAttention).length;
    if (attention == 0) return const SizedBox.shrink();
    return ListTile(
      key: const Key('production-active-jobs'),
      leading: Icon(
        Icons.hourglass_top,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(l10nOf(context).planningActiveJobRow),
      subtitle: Text(l10nOf(context).aiJobsActiveBadge(attention)),
      trailing: const Icon(Icons.chevron_right),
      // Fire-and-forget navigation (no result consumed). The named route is
      // the apply-outcome button's pop target ("back to imports").
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'ai-import-jobs'),
            builder: (_) => const AiImportJobsScreen(),
          ),
        ),
      ),
    );
  }

  /// The AI-import entry: the KI assistant creates planning entities for
  /// this season, so its action lives with the production structure.
  ListTile _aiImportEntry(BuildContext context) {
    return ListTile(
      key: const Key('production-ai-import'),
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(l10nOf(context).navAiImport),
      subtitle: Text(l10nOf(context).planningImportSubtitle),
      trailing: const Icon(Icons.chevron_right),
      // Fire-and-forget navigation (no result consumed).
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AiImportSubmitScreen()),
        ),
      ),
    );
  }

  /// Pushes the block → episode → scene spine with the season DTO as
  /// navigation context (issue #548: the pushed route carries the season
  /// level `PlanningLocation`, so the shell's context strip deepens).
  void _openBlocks(BuildContext context, SeasonView season) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(arguments: PlanningLocation.season(season)),
          builder: (_) => BlocksScreen(season: season),
        ),
      ),
    );
  }

  /// Pull-to-refresh re-runs the blocks projection fetch seam (Drift is
  /// written on success only; the rows below show the resulting state).
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(blocksListFetchProvider(season.id));
    final res = await ref.read(blocksListFetchProvider(season.id).future);
    res.fold((_) {}, (_) {});
  }
}
