// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_episode.dart';
import '../../auth/active_episode_store.dart';
import '../../data/cache/seasons_cache_providers.dart'
    show clockProvider, seasonsView;
import '../episodes/episodes_controller.dart';
import 'active_season_store.dart';
part 'active_episode_scope_repair.g.dart';

/// How long a pick made in this process is protected from the repair's proof
/// of absence (issue #879).
///
/// A pick (episode chip, Script/Schedule row, AI-import "open imported
/// episode") is written *before* the server-side projector carries the new
/// episode, so a `GET /v1/episodes` served inside that gap is a SUCCESSFUL read
/// that does not yet know the row — the projector-lag window §4 of
/// `frontend-flutter/AGENTS.md` models optimistically. Evicting on it would
/// silently reset the filter the user just chose.
///
/// The window is the client's own patience for a lagging projector
/// (`kMaxReconcileAttempts` × `ExponentialBackoffScheduler`: 0,5 + 1 + 2 + 4 s
/// ≈ 7,5 s) with a safety factor. It is only a grace: a pick that is a minute
/// old is evaluable again, and the next cold start always is (the record is
/// in-memory, so a restore never renews it).
const Duration kEpisodeScopeSettleWindow = Duration(seconds: 30);

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
///
/// Nor is a pick younger than [kEpisodeScopeSettleWindow] evicted: a read
/// inside the projector-lag window is not evidence of absence yet (the
/// AI-import apply → "open imported episode" case the review caught).
///
/// The provider is auto-dispose on purpose: the shell is its only watcher, so
/// the repair's lifetime IS the shell's. When `AuthGate` drops the shell on
/// sign-out the element is disposed, and an in-flight eviction's `ref.mounted`
/// fence keeps it from writing or discarding anything afterwards.
@riverpod
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
  // A pick made moments ago is not evidence of absence yet (projector lag).
  // The clock is the injectable seam (deterministic tests, AGENTS.md §6).
  final now = ref.watch(clockProvider).now();
  final picks = ref.watch(episodePickTimesProvider);
  dead.removeWhere(
    (seasonId, episodeId) => !_settled(
      now,
      picks[seasonId],
      seasonId: seasonId,
      episodeId: episodeId,
    ),
  );
  if (dead.isEmpty) return;
  _evictDeadEpisodes(ref, dead);
}

/// `true` when the episode named by ([seasonId], [episodeId]) may be judged on
/// a loaded projection: it is not a pick the live process made inside
/// [kEpisodeScopeSettleWindow].
///
/// A `null` [pick] means the scope was restored from storage (or written by a
/// build without the pick record), so it is by definition older than the
/// window — and a record for a DIFFERENT episode of the same season says
/// nothing about this one: a stale key must never shield a dead scope.
bool _settled(
  DateTime now,
  ({String episodeId, DateTime at})? pick, {
  required String seasonId,
  required String episodeId,
}) {
  if (pick == null || pick.episodeId != episodeId) return true;
  return now.difference(pick.at) >= kEpisodeScopeSettleWindow;
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
///
/// Only scopes whose removal actually SUCCEEDED may reach the in-memory
/// cleanup: with several seasons, one failed write must not let a sibling's
/// success discard a scope whose document is still stored.
void _evictDeadEpisodes(Ref ref, Map<String, String> dead) {
  final store = ref.read(activeEpisodeStoreProvider);
  final entries = dead.entries.toList(growable: false);
  unawaited(
    Future.wait([
      for (final entry in entries)
        store.removeScopeIfMatch(seasonId: entry.key, episodeId: entry.value),
    ]).then((results) {
      if (!ref.mounted) return;
      final removed = <String, String>{
        for (var i = 0; i < entries.length; i++)
          if (results[i].isRight()) entries[i].key: entries[i].value,
      };
      if (removed.isEmpty) return;
      _discardDeadInMemoryScope(ref, removed);
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
