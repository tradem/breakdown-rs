// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_episode.dart';
import '../../auth/active_episode_store.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../episodes/episodes_controller.dart';
import 'active_season_store.dart';
part 'active_episode_scope_repair.g.dart';

/// Evicts persisted active-episode scopes whose episode (or season) the
/// projections no longer serve (issue #879 — C5 of #809).
///
/// The episode-level sibling of [activeScopeRepairProvider] (issue #817): the
/// per-season episode reference in [ActiveEpisodeStore] had the same shape of
/// staleness and was never evicted, so after a dev data reset (#810 / #770) the
/// restore in `AppShell._restoreEpisodeScope` resolved to nothing and the entry
/// stayed in secure storage forever — the operator had to clear app data or the
/// persisted scope by hand (runbook §13).
///
/// Watching this provider performs the repair (the shell watches it once). Two
/// things are removed, both against a **loaded** projection only:
///
/// - the scope of a season the loaded seasons projection no longer serves —
///   the dev-data-reset case, which needs no episode read at all;
/// - the remembered episode of the **active** season once that episode's own
///   block-scoped projection has loaded without it. An episode belongs to
///   exactly one block, and the persisted document names that block, so
///   absence from `(blockId, seasonId)` is absence, not a filter artifact.
///
/// Nothing is evicted while a fetch is loading or has failed: a live-but-
/// unloaded episode must never be dropped. The proofs of absence are the
/// views' `isLoaded` flags — `SeasonsView.isLoaded` (issue #817) and
/// `EpisodesView.isLoaded` (issue #879 adds it, same contract) — because both
/// views deliberately always serve a usable row list: cached rows while a
/// fetch is in flight, retained rows after a failure, so "has rows" says
/// nothing about authority.
@Riverpod(keepAlive: true)
void activeEpisodeScopeRepair(Ref ref) {
  final seasons = ref.watch(seasonsView);
  final persisted = ref.watch(activeEpisodePersistedProvider).value;
  if (persisted == null || persisted.isEmpty) return;
  if (!seasons.isLoaded) return;

  final liveSeasonIds = {for (final season in seasons.rows) season.id};

  // 1. Scopes of a season the projection no longer serves. No episode read is
  //    needed (nor possible): the season itself is the proof of absence.
  final dead = <String, String>{
    for (final entry in persisted.entries)
      if (!liveSeasonIds.contains(entry.key)) entry.key: entry.value.episodeId,
  };

  // 2. The remembered episode of the ACTIVE season, against its own loaded
  //    block projection. Only the active season is probed: every other live
  //    season's scope is repaired when that season becomes active, so a cold
  //    start never fans out into one episode fetch per remembered season.
  final activeSeasonId = ref.watch(activeSeasonResolutionProvider).value?.id;
  if (activeSeasonId != null && liveSeasonIds.contains(activeSeasonId)) {
    final saved = persisted[activeSeasonId];
    if (saved != null) {
      final view = ref.watch(
        episodesViewProvider(saved.blockId, activeSeasonId),
      );
      if (view.isLoaded &&
          !view.rows.any((episode) => episode.id == saved.episodeId)) {
        dead[activeSeasonId] = saved.episodeId;
      }
    }
  }

  if (dead.isEmpty) return;
  _evictDeadEpisodes(ref, dead);
}

/// Evicts the per-season episode scopes named by [dead] (`seasonId` →
/// `episodeId`), then converges the in-memory scope and the persisted map.
///
/// Best-effort and idempotent by construction: every removal is a
/// compare-and-remove against the value that was read
/// ([ActiveEpisodeStore.removeScopeIfMatch]), and the persisted provider is
/// invalidated only after a settled successful write — so a failing store
/// cannot turn this into a rebuild loop (the next cold start retries
/// naturally), and a converged state performs no write at all.
void _evictDeadEpisodes(Ref ref, Map<String, String> dead) {
  final store = ref.read(activeEpisodeStoreProvider);
  unawaited(
    Future.wait([
      for (final entry in dead.entries)
        store.removeScopeIfMatch(seasonId: entry.key, episodeId: entry.value),
    ]).then((results) {
      final wrote = results.any((res) => res.isRight());
      if (!ref.mounted || !wrote) return;
      _discardDeadInMemoryScope(ref, dead);
      ref.invalidate(activeEpisodePersistedProvider);
    }),
  );
}

/// Drops the IN-MEMORY sticky scope when it still names an evicted pair.
///
/// Without this the dead episode would keep rendering in the shell's episode
/// chip: `AppShell._restoreEpisodeScope` deliberately keeps an in-memory scope
/// whose season matches, so nothing else would drop it before the next cold
/// start. The check is a compare-and-remove on the live value (season AND
/// episode), so a fresh pick that landed after the stale read — in memory
/// already, its document not yet written, or written between the store read and
/// this branch — is never discarded.
void _discardDeadInMemoryScope(Ref ref, Map<String, String> dead) {
  final live = ref.read(activeEpisodeProvider);
  if (live == null) return;
  if (dead[live.seasonId] != live.episodeId) return;
  ref.read(activeEpisodeProvider.notifier).discard();
}
