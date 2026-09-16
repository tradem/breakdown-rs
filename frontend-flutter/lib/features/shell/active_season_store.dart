// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../data/cache/shell_state_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
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
/// start simply opens the Season tab without an active season).
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
  final sub = switch (ref.watch(authSessionControllerProvider)) {
    AsyncData(:final value) => value?.sub,
    _ => null,
  };
  final res = await ref
      .watch(shellStateDaoProvider)
      .read(activeSeasonKeyFor(sub));
  return res.fold((_) => null, (entry) => entry?.value);
}

/// Resolves the persisted active-season id against the seasons projection.
///
/// `null` when nothing is persisted or the id matches no row of the live
/// (TTL-governed) seasons view. Re-runs whenever either side changes, so
/// the resolution converges after a seasons refetch.
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
