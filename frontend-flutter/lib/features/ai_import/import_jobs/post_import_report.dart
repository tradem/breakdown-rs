// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/active_episode.dart';
import '../../../data/cache/hierarchy_cache_dao.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../../data/season_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shell/shell_controller.dart';
import 'apply_controller.dart';
import 'job_status_controller.dart';

part 'post_import_report.g.dart';

/// The episode an apply landed in, as the app names it afterwards (issue #759).
///
/// `episodeNumber` is non-null by construction: the destination is the Script
/// view under the sticky episode scope, and that scope carries the number its
/// chip renders. A target without a resolvable number is NOT routed to — the
/// resolution returns `null` and the preview keeps the outcome card and says
/// so, instead of landing the user on a half-scoped Script view.
class AiPostImportTarget {
  const AiPostImportTarget({
    required this.season,
    required this.blockId,
    required this.blockNumber,
    required this.episodeId,
    required this.episodeNumber,
    required this.episodeName,
    this.others = const <AppliedEpisode>[],
  });

  /// The season the import wrote into (resolved from the read cache — the
  /// Script view is season-scoped and renders nothing without it).
  final SeasonView season;

  /// The block the imported episode belongs to (the request scope).
  final String blockId;

  /// The block's number when the cache knew it — `null` is honest absence (the
  /// block chip backfills its label from the cache, never from a guess).
  final int? blockNumber;

  final String episodeId;
  final int episodeNumber;
  final String? episodeName;

  /// The OTHER episodes this apply dispatched rows into (a multi-episode
  /// import), each with its own row count. Never empty silently: a document
  /// that spans episodes must not move the user away from rows that went
  /// elsewhere without naming them.
  final List<AppliedEpisode> others;
}

/// The per-target choice of [pickAppliedTargetEpisode].
typedef AppliedTargetChoice = ({
  AppliedEpisode target,
  List<AppliedEpisode> others,
});

/// Which episode the app opens after a successful apply (issue #759).
///
/// Rules, in order:
/// 1. the episode the REVIEWER targeted (`episode_id` of the apply request) —
///    the one the review screen promised the rows to — when the response lists
///    it. A multi-group document may land rows in several episodes; the user is
///    moved to the episode they explicitly confirmed, never to the biggest.
/// 2. otherwise the episode that received the MOST rows (ties keep the server's
///    order), so a document whose target is absent still opens where its
///    material actually is.
/// 3. no applied episode at all (a schedule apply merges onto the project's
///    existing scenes and days) → `null`: there is nothing to open.
///
/// Pure and side-effect free (unit-tested directly): the choice is the same for
/// the navigation and for the report the destination renders.
AppliedTargetChoice? pickAppliedTargetEpisode(
  Iterable<AppliedEpisode> episodes, {
  required String? requestEpisodeId,
}) {
  final rows = episodes.toList();
  if (rows.isEmpty) return null;
  AppliedEpisode? target;
  if (requestEpisodeId != null && requestEpisodeId.isNotEmpty) {
    for (final row in rows) {
      if (row.id == requestEpisodeId) {
        target = row;
        break;
      }
    }
  }
  if (target == null) {
    for (final row in rows) {
      if (target == null || row.appliedCount > target.appliedCount) {
        target = row;
      }
    }
  }
  final chosen = target!;
  return (
    target: chosen,
    others: [
      for (final row in rows)
        if (row.id != chosen.id) row,
    ],
  );
}

/// What the destination keeps from a completed apply (issue #759).
///
/// The apply used to report once, in place, and the user was left on the review
/// screen; navigating away would have dropped `unapplied_outfits` and the
/// additional episodes of a multi-episode import on the floor. The report is
/// therefore published as state the Script view renders — dismissible, but
/// never silently discarded.
class PostImportReport {
  const PostImportReport({
    required this.outcome,
    required this.episodeId,
    this.others = const <AppliedEpisode>[],
    this.skippedDayLabels = const <String>[],
  });

  /// The apply's own 200 response (counts + `unapplied_outfits`).
  final ApplyAiImportResponse outcome;

  /// The episode the app opened.
  final String episodeId;

  /// The other episodes the apply landed rows in.
  final List<AppliedEpisode> others;

  /// The reviewer-rejected day groups, already resolved to their display
  /// labels (issue #706) — reported at the destination too, never silent.
  final List<String> skippedDayLabels;
}

/// The published post-import report, kept until the user dismisses it.
///
/// `keepAlive: true`: the report is published at the END of the import stack
/// and consumed by the Script view, which is a DIFFERENT route tree node — the
/// value must survive the import stack's pop and any later tab switch until the
/// user closes it.
@Riverpod(keepAlive: true)
class AiPostImportReport extends _$AiPostImportReport {
  @override
  PostImportReport? build() => null;

  void publish(PostImportReport report) => state = report;

  void dismiss() => state = null;
}

/// The shared outcome summary line (`aiApplyOutcome` / `aiApplyOutcomeScript`).
///
/// Both the review screen's inline outcome card and the destination banner use
/// it, so the two can never tell different stories about the same apply.
String aiApplyOutcomeLine(
  AppLocalizations l10n,
  ApplyAiImportResponse outcome,
) =>
    outcome.createdCharacters > 0 ||
        outcome.createdPieces > 0 ||
        outcome.createdOutfits > 0 ||
        outcome.unappliedOutfits.isNotEmpty
    // The generated signature orders the placeholders alphabetically
    // (applied, characters, outfits, pieces), not in message order — pass
    // them in that order.
    ? l10n.aiApplyOutcomeScript(
        '${outcome.appliedCount}',
        '${outcome.createdCharacters}',
        '${outcome.createdOutfits}',
        '${outcome.createdPieces}',
      )
    : l10n.aiApplyOutcome(
        '${outcome.appliedCount}',
        '${outcome.createdDays}',
        '${outcome.plannedSceneShoots}',
      );

/// Why an outfit row was not fully applied — the typed wire enum, localized
/// (never parsed out of server prose).
String aiUnappliedOutfitReasonCopy(
  AppLocalizations l10n,
  UnappliedOutfitReason reason,
) => switch (reason) {
  UnappliedOutfitReason.characterNotPlanned =>
    l10n.aiApplyUnappliedReasonCharacterNotPlanned,
  UnappliedOutfitReason.characterUnavailable =>
    l10n.aiApplyUnappliedReasonCharacterUnavailable,
  UnappliedOutfitReason.pieceRejected =>
    l10n.aiApplyUnappliedReasonPieceRejected,
  UnappliedOutfitReason.createRejected =>
    l10n.aiApplyUnappliedReasonCreateRejected,
  UnappliedOutfitReason.notesRejected =>
    l10n.aiApplyUnappliedReasonNotesRejected,
  UnappliedOutfitReason.bindingRejected =>
    l10n.aiApplyUnappliedReasonBindingRejected,
  UnappliedOutfitReason.beatRejected => l10n.aiApplyUnappliedReasonBeatRejected,
  _ => l10n.commonUnknown,
};

/// Resolves WHERE the app opens after a successful apply (issue #759), or
/// `null` when the destination cannot be resolved honestly.
///
/// Reads only seams the client already trusts for navigation context:
/// the job's cached block (the request scope), the block row's season id, the
/// seasons read cache (the Script view is season-scoped), and — only when the
/// wire carried no number — the block's CACHED episode rows. No network read on
/// the navigation path, no invented ids, no fabricated numbers: every missing
/// piece answers `null`, and the caller keeps the outcome card plus an honest
/// hint instead of a half-navigation.
///
/// The target list comes from the response first and from the job's
/// **persisted** summary second (issue #864). The fallback is load-bearing: a
/// re-apply of an already-applied preview dispatches nothing (every row is
/// settled by its mapping), so its response names no episode at all, while the
/// server-derived job summary still names where the earlier run put the rows.
/// Without it the hop would fall back to the request's episode — or to nothing —
/// although a durable answer exists. Both sources are read from the cache, so
/// the navigation path still never waits for the network.
Future<AiPostImportTarget?> resolvePostImportTarget(
  WidgetRef ref, {
  required String jobId,
  required ApplyAiImportResponse outcome,
  String? requestEpisodeId,
}) async {
  final wire = outcome.appliedEpisodes ?? const <AppliedEpisode>[];
  final candidates = wire.isEmpty
      ? await ref.read(aiJobAppliedEpisodesProvider(jobId).future)
      : wire;
  final choice = pickAppliedTargetEpisode(
    candidates,
    requestEpisodeId: requestEpisodeId,
  );
  if (choice == null) return null;

  final info = await ref.read(aiJobBlockInfoProvider(jobId).future);
  final blockId = info?.blockId;
  if (blockId == null || blockId.isEmpty) return null;

  final seasonId = await ref.read(aiApplyJobSeasonIdProvider(jobId).future);
  if (seasonId == null || seasonId.isEmpty) return null;

  final season = await _cachedSeason(ref, seasonId);
  if (season == null) return null;

  var number = choice.target.number;
  var name = choice.target.name;
  if (number == null) {
    // Cache-only fallback (CodeRabbit #802): this is a NAVIGATION path, so it
    // must never wait for — or depend on — the network. The block's cached
    // episode rows are the same read model the Script view composes from; a
    // row the cache does not hold leaves the number unknown, which is NOT a
    // reason to invent one (the target then stays unresolved).
    final cached = await EpisodeCacheDao(ref.read(cacheDatabaseProvider))
        .readByBlock(blockId);
    for (final row in cached) {
      if (row.id == choice.target.id) {
        number = row.number;
        name ??= row.name;
        break;
      }
    }
  }
  if (number == null) return null;

  final block = await BlockCacheDao(ref.read(cacheDatabaseProvider))
      .readById(blockId);

  return AiPostImportTarget(
    season: season,
    blockId: blockId,
    blockNumber: block?.number,
    episodeId: choice.target.id,
    episodeNumber: number,
    episodeName: name,
    others: choice.others,
  );
}

/// The season DTO from the read cache — the same discipline the import target
/// line uses for its season number: a label the cache does not hold stays
/// unknown instead of triggering a read on a navigation path.
Future<SeasonView?> _cachedSeason(WidgetRef ref, String seasonId) async {
  final repo = ref.read(seasonRepositoryProvider);
  final rows = await _readCachedSeasons(repo);
  for (final season in rows) {
    if (season.id == seasonId) return season;
  }
  return null;
}

Future<List<SeasonView>> _readCachedSeasons(SeasonRepository repo) async {
  try {
    final res = await repo.readCached();
    return res.getRight().toNullable() ?? const <SeasonView>[];
  } on Object {
    // A cache read failure degrades to "season unknown" — never a thrown
    // exception on the post-apply path.
    return const <SeasonView>[];
  }
}

/// Leaves the import stack and lands on the imported material (issue #759).
///
/// Order matters and is asserted by the widget tests:
/// 1. publish the report FIRST, so the destination's very first build can
///    render it (the Script view is always mounted in the shell's
///    `IndexedStack`);
/// 2. switch the sticky scopes (episode + its block, and the active season when
///    it is not the import's season) — the Script view filters on them, so the
///    imported episode is what the user sees;
/// 3. select the Script destination;
/// 4. pop the import stack (`jobs → job status → preview`) back to the tab
///    root, so the review screen is actually left.
///
/// The season write goes through [ShellController.setActiveSeason] only when the
/// active season differs: a needless write would persist the same reference
/// again on every apply and invalidate the resolution provider for nothing.
void openImportedEpisode(
  BuildContext context,
  WidgetRef ref, {
  required AiPostImportTarget target,
  required PostImportReport report,
}) {
  ref.read(aiPostImportReportProvider.notifier).publish(report);

  // Issue #765: `ActiveEpisode.set` is the ONE seam that also establishes the
  // block scope (an episode implies its block), so the Script view's reads can
  // never go headerless.
  ref
      .read(activeEpisodeProvider.notifier)
      .set(
        seasonId: target.season.id,
        blockId: target.blockId,
        episodeId: target.episodeId,
        episodeNumber: target.episodeNumber,
        episodeName: target.episodeName,
        blockNumber: target.blockNumber,
      );

  final shell = ref.read(shellControllerProvider.notifier);
  if (ref.read(shellControllerProvider).activeSeason?.id != target.season.id) {
    shell.setActiveSeason(target.season);
  }
  shell.selectTab(kScriptTabIndex);

  Navigator.of(context).popUntil((route) => route.isFirst);
}
