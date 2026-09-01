// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';
import 'cache_database.dart';
import 'clock.dart';
import 'season_cache_dao.dart';
import 'seasons_view.dart';
import '../season_repository.dart';

part 'seasons_cache_providers.g.dart';

/// Injectable clock for deterministic cache/TTL tests (D2).
@riverpod
Clock clock(Ref ref) => Clock.system;

/// Generated API client.
///
/// NOTE: production must inject the pinned-CA Dio from
/// `lib/src/network/api_client.dart` here (deferred to the wiring/auth change).
/// For now a default `BreakdownApi()` is sufficient — the list fetch is
/// overridden in tests and the single-entity path is exercised by later
/// changes.
@riverpod
BreakdownApi apiClient(Ref ref) => BreakdownApi();

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
  return repo.fetchAndCacheList(
    () async =>
        const Left(ProblemError(code: 'transport.seasons_list_unavailable')),
    clock: clock,
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
    unawaited(() async {
      final cached = (await repo.readCached()).getOrElse(
        (_) => const <SeasonView>[],
      );
      // The container may be disposed while the cache read is in flight
      // (e.g. a screen torn down right after cold start) — touching `ref`
      // then would throw out of a fire-and-forget body.
      if (!ref.mounted) return;
      ref.read(seasonsPrevRowsProvider.notifier).set(cached);
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

/// The projection a screen reads (Design Decision D1/D4 selector).
///
/// Always exposes a usable value: during loading it serves the seeded cached
/// rows; on error it serves the retained snapshot with a stale marker and the
/// error; on success it serves the fresh rows.
final seasonsView = Provider<SeasonsView>((ref) {
  final async = ref.watch(seasonsViewControllerProvider);
  final prev = ref.watch(seasonsPrevRowsProvider);
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => SeasonsView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => SeasonsView(rows: prev, isStale: prev.isNotEmpty),
  };
});
