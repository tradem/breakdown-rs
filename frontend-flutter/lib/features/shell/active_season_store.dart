// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_block_store.dart';
import '../../auth/auth_providers.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/cache/seasons_view.dart';
import '../../data/cache/shell_state_cache_dao.dart';
part 'active_season_store.g.dart';

/// Persisted active-season reference (design D5: active season =
/// last-opened season, restored across cold starts).
///
/// The store persists **only the season id** (an opaque reference) under
/// [kActiveSeasonKey]. The referenced projection row is re-validated
/// against the TTL-stamped seasons read cache on every boot
/// ([activeSeasonResolutionProvider]) — a persisted id whose season no
/// longer exists (or whose cached row has expired and is not re-fetched)
/// resolves to `null`, never to a stale DTO ("TTL-compliant by
/// construction").
///
/// Persistence is best-effort: a store failure never breaks the in-memory
/// active season — it degrades to "nothing persisted" (the next cold
/// start simply lands on the Cast view without an active season).
const String kActiveSeasonKey = 'active_season_id';

/// Session-scoped persistence key (CodeRabbit review fix): the reference
/// is stored under `active_season_id@<sub>` so identity B never resolves
/// identity A's season — the key space dies with the session, mirroring
/// the identity-scoped secure-storage seam of `ActiveBlockStore`.
String activeSeasonKeyFor(String? sub) => '$kActiveSeasonKey@${sub ?? ''}';

/// The [ShellStateDao] seam (auto codegen so tests override with an
/// in-memory-Drift-backed instance via `overrideWith`).
@riverpod
ShellStateDao shellStateDao(Ref ref) =>
    ShellStateDao(ref.watch(cacheDatabaseProvider));

/// The session-scoped shell-state key currently in force.
///
/// One source for the key space: the read ([activeSeasonPersistedProvider])
/// and the repair ([activeScopeRepairProvider], issue #817) derive the key
/// from the same provider, so an eviction can only ever target the document
/// the resolution actually read — identity B never deletes identity A's
/// reference.
@riverpod
String activeSeasonStorageKey(Ref ref) =>
    activeSeasonKeyFor(switch (ref.watch(authSessionControllerProvider)) {
      AsyncData(:final value) => value?.sub,
      _ => null,
    });

/// The persisted active-season id FOR THE CURRENT SESSION, kept alive.
///
/// Session-scoped (CodeRabbit review fix): the key carries the
/// authenticated `sub`, so a cold start only ever hydrates the signed-in
/// identity's reference. A store failure degrades to `null` ("nothing
/// persisted") right here — failing the provider instead would arm the
/// Riverpod auto-retry timers (never settle under `pumpAndSettle` in
/// widget tests) and buy nothing in production.
@Riverpod(keepAlive: true)
Future<String?> activeSeasonPersisted(Ref ref) async {
  final res = await ref
      .watch(shellStateDaoProvider)
      .read(ref.watch(activeSeasonStorageKeyProvider));
  return res.fold((_) => null, (entry) => entry?.value);
}

/// Resolves the persisted active-season id against the seasons projection.
///
/// `null` when nothing is persisted or the id matches no row of the live
/// (TTL-governed) seasons view. Re-runs whenever either side changes, so
/// the resolution converges after a seasons refetch.
///
/// A persisted id that a *loaded* view no longer contains is dead state (the
/// dev-data-reset case of #810 / #770): the resolution refuses to return it,
/// and [activeScopeRepairProvider] evicts it (issue #817, the repair half of
/// #809). The resolution itself stays a pure resolver — no eviction side
/// effect — so its `.future` remains a reliable single-build await for
/// callers and tests.
@Riverpod(keepAlive: true)
Future<SeasonView?> activeSeasonResolution(Ref ref) async {
  final persisted = await ref.watch(activeSeasonPersistedProvider.future);
  if (persisted == null) return null;
  final view = ref.watch(seasonsView);
  for (final season in view.rows) {
    if (season.id == persisted) return season;
  }
  return null;
}

/// Evicts persisted shell state whose season the projection no longer serves
/// (issue #817 — the repair half of #809).
///
/// #809 made the AI-configuration entry *tolerate* a dead anchor; this is the
/// half that repairs it, so a dev data reset (#810 / #770) stops degrading
/// scope-derived UI until the user clears app data by hand.
///
/// Watching this provider performs the repair (the shell watches it once); it
/// re-runs whenever the seasons projection, the persisted anchor or the
/// persisted per-season block scopes change. Two things are removed:
///
/// - the anchor (`shell_state.active_season_id@<sub>`) once the seasons view
///   has loaded and does not contain it — compare-and-remove on the value
///   that was read, so a fresh pick that landed after this read survives;
/// - every persisted per-season block scope whose season is gone.
///   `blockScopeResolution` evicts a scope only per *resolved* season, which
///   never happens for a season the projection no longer serves.
///
/// Nothing is evicted while the seasons fetch is loading or failed: a
/// live-but-unloaded season must never be dropped. The proof of absence is
/// [SeasonsView.isLoaded] — the view deliberately always exposes a usable row
/// list (cached while the fetch is in flight, retained after a failure), so
/// "has rows" alone would treat an unloaded projection as authoritative.
@Riverpod(keepAlive: true)
void activeScopeRepair(Ref ref) {
  final view = ref.watch(seasonsView);
  final persisted = ref.watch(activeSeasonPersistedProvider).value;
  final blockScopes = ref.watch(activeBlockPersistedProvider).value;
  if (!view.isLoaded) return;
  _evictGoneSeasons(
    ref,
    liveSeasonIds: {for (final season in view.rows) season.id},
    persisted: persisted,
    blockScopes: blockScopes,
  );
}

/// Evicts the persisted state whose season a LOADED seasons view does not
/// contain (issue #817).
///
/// Best-effort and idempotent by construction: every removal is a
/// compare-and-remove against the value that was read, and the persisted
/// providers are invalidated only after a settled successful write — so a
/// failing store cannot turn this into a rebuild loop (the next cold start
/// retries naturally), and a converged state performs no write at all.
void _evictGoneSeasons(
  Ref ref, {
  required Set<String> liveSeasonIds,
  required String? persisted,
  required Map<String, PersistedBlockScope>? blockScopes,
}) {
  // 1. The anchor: conditional on the value that was read, so a fresh pick
  //    that landed after this read is never deleted (`ShellStateDao
  //    .deleteIfValue` is the shell-state twin of `removeScopeIfMatch`).
  if (persisted != null && !liveSeasonIds.contains(persisted)) {
    final key = ref.read(activeSeasonStorageKeyProvider);
    unawaited(
      ref
          .read(shellStateDaoProvider)
          .deleteIfValue(key: key, value: persisted)
          .then((res) {
            if (!ref.mounted || res.isLeft()) return;
            ref.invalidate(activeSeasonPersistedProvider);
          }),
    );
  }

  // 2. Per-season block scopes of a season the projection no longer serves.
  //    Conditional per entry (`removeScopeIfMatch`, not `removeScope`): a
  //    fresh pick for that season must survive regardless of scheduling.
  if (blockScopes == null) return;
  final gone = [
    for (final entry in blockScopes.entries)
      if (!liveSeasonIds.contains(entry.key)) entry,
  ];
  if (gone.isEmpty) return;
  final store = ref.read(activeBlockStoreProvider);
  unawaited(
    Future.wait([
      for (final entry in gone)
        store.removeScopeIfMatch(
          seasonId: entry.key,
          blockId: entry.value.blockId,
        ),
    ]).then((results) {
      final wrote = results.any((res) => res.isRight());
      if (!ref.mounted || !wrote) return;
      ref.invalidate(activeBlockPersistedProvider);
    }),
  );
}
