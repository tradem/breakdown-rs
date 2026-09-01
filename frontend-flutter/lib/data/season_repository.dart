// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/season_cache_dao.dart';

/// Read/write repository for the `Season` aggregate boundary.
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [SeasonCacheDao] (Design Decision
/// D1: the repository is the single owner of network + cache writes).
///
/// Cache-write discipline:
/// * a successful fetch **upserts** the row(s) inside a transaction and
///   returns [Right];
/// * a fetch [Left] returns the error **without mutating the cache** (no
///   partial writes, D1);
/// * the screen reads only through [readCached] / the `seasonsView` provider,
///   never the API client or the cache directly.
class SeasonRepository extends BaseRepository {
  const SeasonRepository(super.api, this.cache);

  final SeasonCacheDao cache;

  // --- Network-only write commands (unchanged contract) ---------------------

  /// Creates a new season.
  Future<Result<IdVersionResponse>> create(CreateSeasonRequest request) => run(
    () => api.getHandlersApi().createSeason(createSeasonRequest: request),
  );

  /// Fetches a single season by id.
  Future<Result<SeasonView>> get(String id) =>
      run(() => api.getHandlersApi().getSeason(id: id));

  /// Renames an existing season.
  Future<Result<int>> rename(String id, RenameSeasonRequest request) => run(
    () =>
        api.getHandlersApi().renameSeason(id: id, renameSeasonRequest: request),
  );

  // --- Cache-backed read path (Design Decision D1) -------------------------

  /// Single-entity fetch + cache: GET season, upsert on success, no mutation
  /// on failure (D1).
  Future<Result<SeasonView>> getAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async {
    final fetched = await run(() => api.getHandlersApi().getSeason(id: id));
    return _applyOne(fetched, clock);
  }

  /// Test/DI seam: applies a [fetched] single-entity result to the cache
  /// without performing any network call. On [Right] upserts; on [Left]
  /// returns the error unchanged and leaves the cache untouched.
  Future<Result<SeasonView>> getAndCacheFrom(
    Result<SeasonView> fetched, {
    Clock clock = Clock.system,
  }) => _applyOne(fetched, clock);

  Future<Result<SeasonView>> _applyOne(
    Result<SeasonView> fetched,
    Clock clock,
  ) => fetched.match((err) async => Left<ProblemError, SeasonView>(err), (
    view,
  ) async {
    try {
      await cache.upsert(view, clock.now());
    } on Object {
      // A cache write failure is a transport-level fault, not a server
      // problem; surface it as a Result so callers can handle it
      // (AGENTS.md §5: no throw in data/, return Result).
      return const Left(ProblemError(code: 'cache.write_failed'));
    }
    return Right(view);
  });

  /// Collection fetch + snapshot-replace reconciliation (Design Decision D3).
  ///
  /// [fetch] is injected because the generated client has no seasons list
  /// endpoint yet (tracked separately); production passes the future list
  /// call, tests pass a fake. On [Right] it applies the snapshot (upsert-all +
  /// delete missing ids, one transaction) and returns the rows. On [Left] it
  /// returns the error **without touching the cache** (D1).
  Future<Result<List<SeasonView>>> fetchAndCacheList(
    Future<Result<List<SeasonView>>> Function() fetch, {
    Clock clock = Clock.system,
  }) async {
    final result = await fetch();
    return result.match(
      (err) async => Left<ProblemError, List<SeasonView>>(err),
      (views) async {
        try {
          await cache.applySnapshot(views, clock.now());
        } on Object {
          // A cache write failure is a transport-level fault, not a server
          // problem; surface it as a Result so callers can handle it
          // (AGENTS.md §5: no throw in data/, return Result).
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(views);
      },
    );
  }

  /// Pure Drift read (no network) of every cached season (D1: controller
  /// seeds `prevRows` from this before triggering the network fetch).
  Future<Result<List<SeasonView>>> readCached() async {
    try {
      final rows = await cache.readAll();
      return Right(rows);
    } on Object {
      // A cache read failure is a transport-level fault, not a server problem.
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns the seasons read projection from the Drift cache — the
  /// authoritative row source the screen renders (first-screen-seasons
  /// Task 2.2; the spec's `SeasonDto` is the generated `SeasonView`).
  ///
  /// Network freshness is owned by the `seasonsListFetchProvider` seam +
  /// the cache controller ([fetchAndCacheList] writes on success only);
  /// this method is the pure read surface (D1 there: the screen never
  /// touches the API client or the DAO directly).
  Future<Result<List<SeasonView>>> list() => readCached();

  /// Returns `true` when any cached row is older than [ttl] per [clock] (D2).
  Future<bool> isCacheStale({
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) => cache.isAnyExpired(ttl, clock: clock);
}
