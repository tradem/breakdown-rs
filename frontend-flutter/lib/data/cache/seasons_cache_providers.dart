// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: hy3 (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../src/network/api_client.dart';
import 'cache_database.dart';
import 'cache_generation.dart';
import 'clock.dart';
import 'season_cache_dao.dart';
import 'seasons_view.dart';
import '../season_repository.dart';

part 'seasons_cache_providers.g.dart';

/// Injectable clock for deterministic cache/TTL tests (D2).
@riverpod
Clock clock(Ref ref) => Clock.system;

/// Generated API client over the rebuildable pinned Dio (task 6.3 —
/// follows runtime base-URL switches; same pinned `SecurityContext`).
@riverpod
BreakdownApi apiClient(Ref ref) => BreakdownApi(dio: ref.watch(apiDioProvider));

/// The read-projection cache database.
///
/// Defaults to an in-memory database so the cache layer is self-contained and
/// testable. Production wiring MUST override this with a file-backed executor
/// (deferred to `first-screen-seasons`, which owns the persistence path).
@riverpod
CacheDatabase cacheDatabase(Ref ref) => CacheDatabase();

/// Season repository: owns network + Drift cache writes (D1).
@riverpod
SeasonRepository seasonRepository(Ref ref) => SeasonRepository(
  ref.watch(apiClientProvider),
  SeasonCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected list-fetch seam (Design Decision D3).
///
/// The generated client has no seasons list endpoint yet (tracked separately),
/// so the default surfaces a `not_implemented` error; production wiring
/// replaces the body with `repo.fetchAndCacheList(() => repo.fetchSeasonsList())`
/// once `GET /v1/seasons` lands. Tests override this provider with a fake that
/// writes the cache via `repo.fetchAndCacheList(...)`.
@riverpod
Future<Result<List<SeasonView>>> seasonsListFetch(Ref ref) {
  final repo = ref.watch(seasonRepositoryProvider);
  final clock = ref.watch(clockProvider);
  // Generation fence (task 6.3): a base switch / sign-out reset that lands
  // while this fetch is in flight discards its cache write (no cross-identity
  // rows). Unwatched-after-dispose reads as stale too — dead screens cannot
  // persist.
  final generation = ref.watch(cacheGenerationProvider);
  return repo.fetchAndCacheList(
    () async =>
        const Left(ProblemError(code: 'transport.seasons_list_unavailable')),
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot, updated by [SeasonsViewController] after every
/// successful read (D1/D4). Lets the `seasonsView` selector serve cached rows
/// even when the async controller is in `AsyncError`.
final seasonsPrevRowsProvider =
    NotifierProvider<_SeasonsPrevRows, List<SeasonView>>(_SeasonsPrevRows.new);

class _SeasonsPrevRows extends Notifier<List<SeasonView>> {
  @override
  List<SeasonView> build() => const [];

  void set(List<SeasonView> rows) => state = rows;
}

/// Read-projection controller (Design Decisions D1–D4).
///
/// It maps the injected [seasonsListFetchProvider] `Result` into an
/// `AsyncValue<SeasonsView>`: on success it emits fresh rows; on fetch `Err`
/// it emits `AsyncError` (never silently discarded — Task 3.3) while the
/// derived `seasonsView` selector serves the retained snapshot. Reading the
/// cache FIRST (seeding `seasonsPrevRowsProvider`) makes offline cold start
/// render cached rows. The controller is a sync `Notifier` (not an
/// `AsyncNotifier`) so a fetch `Err` surfaces as `AsyncError` rather than
/// triggering Riverpod's async-notifier retry loop.
@Riverpod(keepAlive: false)
class SeasonsViewController extends _$SeasonsViewController {
  @override
  AsyncValue<SeasonsView> build() {
    final repo = ref.watch(seasonRepositoryProvider);

    // D1: read the cache FIRST (offline cold start) and seed the retained
    // snapshot store used by `seasonsView`. This runs once per build; the
    // derived selector serves these rows while the network fetch is pending
    // or has failed. Fire-and-forget is intentional: `build()` is sync and
    // must return the placeholder immediately, so the cache read is scheduled
    // via `unawaited` rather than awaited (discard_result rule, AGENTS.md §5).
    // The seed never overwrites a populated snapshot with an empty read:
    // after a reset clear the database is briefly empty while the retained
    // rows are still the last-good state (stale banner over them, task 6.7).
    // Identity changes reset the snapshot explicitly (`SessionReset`).
    unawaited(() async {
      final cached = (await repo.readCached()).getOrElse(
        (_) => const <SeasonView>[],
      );
      // The container may be disposed while the cache read is in flight
      // (e.g. a screen torn down right after cold start) — touching `ref`
      // then would throw out of a fire-and-forget body.
      if (!ref.mounted) return;
      if (cached.isNotEmpty || ref.read(seasonsPrevRowsProvider).isEmpty) {
        ref.read(seasonsPrevRowsProvider.notifier).set(cached);
      }
    }());

    // Map the injected fetch `Result` into our projection's AsyncValue. The
    // fetch provider resolves to a `Result` (never throws), so there is no
    // async-notifier retry loop (D4).
    final fetch = ref.watch(seasonsListFetchProvider);
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        // D4: surface AsyncError; retained rows stay in seasonsPrevRowsProvider.
        (err) => AsyncValue<SeasonsView>.error(err, StackTrace.current),
        // After a successful snapshot the cache rows are fresh (D2).
        (rows) => AsyncValue<SeasonsView>.data(
          SeasonsView(rows: rows, isStale: false),
        ),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<SeasonsView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<SeasonsView>.loading(),
    };
  }

  /// Create command with on-write-invalidate (Task 3.2): a successful write
  /// refetches the affected read projection so the cache converges.
  Future<Result<IdVersionResponse>> createSeason(
    CreateSeasonRequest request,
  ) async {
    final repo = ref.read(seasonRepositoryProvider);
    final res = await repo.create(request);
    if (res.isRight()) {
      ref.invalidate(seasonsListFetchProvider);
      ref.invalidateSelf();
    }
    return res;
  }

  /// Rename command with on-write-invalidate (Task 3.2).
  Future<Result<int>> renameSeason(
    String id,
    RenameSeasonRequest request,
  ) async {
    final repo = ref.read(seasonRepositoryProvider);
    final res = await repo.rename(id, request);
    if (res.isRight()) {
      ref.invalidate(seasonsListFetchProvider);
      ref.invalidateSelf();
    }
    return res;
  }
}

/// TTL-based cache staleness for the seasons projection (issue #366).
///
/// Backed by [SeasonRepository.isCacheStale] (client-only `cachedAt` + the
/// injectable [clockProvider]); a staleness-check failure resolves to
/// `false` (fail-closed: no banner when staleness itself is unknown — the
/// error path still banners a failed refetch serving retained rows).
@riverpod
Future<bool> seasonsCacheStale(Ref ref) async {
  final repo = ref.watch(seasonRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (Design Decision D1/D4 selector).
///
/// Always exposes a usable value: during loading it serves the seeded cached
/// rows; on error it serves the retained snapshot with a stale marker and the
/// error; on success it serves the fresh rows.
final seasonsView = Provider<SeasonsView>((ref) {
  final async = ref.watch(seasonsViewControllerProvider);
  final prev = ref.watch(seasonsPrevRowsProvider);
  // TTL-based staleness (issue #366): a fresh cache served while a normal
  // refetch is in flight is NOT stale — the banner shows only for an
  // expired cache or a failed refetch serving retained rows. Unknown
  // (still loading / failed) staleness reads as fresh (fail-closed).
  final ttlStale = ref.watch(seasonsCacheStaleProvider).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => SeasonsView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => SeasonsView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
});
