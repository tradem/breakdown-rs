// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/block_repository.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/hierarchy_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'blocks_state.dart';

part 'blocks_controller.g.dart';

/// Block repository: owns network + Drift cache writes.
@riverpod
BlockRepository blockRepository(Ref ref) => BlockRepository(
  ref.watch(apiClientProvider),
  BlockCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected season-scoped list-fetch seam: `GET /v1/blocks?season_id=…`
/// (writes Drift on success, never on failure). Tests override this provider
/// with a fake.
@riverpod
Future<Result<List<BlockView>>> blocksListFetch(
  Ref ref,
  String seasonId,
) async {
  final repo = ref.watch(blockRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listBySeason(
    seasonId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per season, so the view selector can serve
/// cached rows while the fetch is loading or has failed.
@Riverpod(keepAlive: true)
class BlocksPrevRows extends _$BlocksPrevRows {
  @override
  List<BlockView> build(String seasonId) => const [];

  void set(List<BlockView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern): the
/// screen consumes only this value — never the API client or the cache
/// directly. [rows] is the latest good snapshot; [isStale] marks expired
/// cache / failed refetch; [error] carries a surfaced fetch failure.
class BlocksView {
  const BlocksView({required this.rows, required this.isStale, this.error});

  final List<BlockView> rows;

  /// `true` when the served rows are from an expired cache or a failed
  /// refetch left only stale cached rows.
  final bool isStale;

  /// Non-null when the last fetch failed. Rows are still served (retained
  /// stale rows) so the screen never goes blank on a transient error.
  final ProblemError? error;
}

/// Read-projection controller.
///
/// Maps the injected [blocksListFetchProvider] `Result` into an
/// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
/// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
/// store but never reads it back through a watch, so its own writes can
/// never invalidate it (no seed/rebuild loop). Consumers read through
/// [blocksViewProvider].
@Riverpod(keepAlive: false)
class BlocksViewController extends _$BlocksViewController {
  @override
  AsyncValue<BlocksView> build(String seasonId) {
    final repo = ref.watch(blockRepositoryProvider);

    // Read the cache FIRST (offline cold start) and seed the retained
    // snapshot store used by `blocksViewProvider`. Fire-and-forget:
    // `build()` is sync. The seed never overwrites a populated snapshot
    // with an empty read.
    unawaited(() async {
      final cached = (await repo.readCached(seasonId))
          .getOrElse((_) => const <BlockView>[]);
      // The container may be disposed while the cache read is in flight.
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(blocksPrevRowsProvider(seasonId)).isEmpty) {
        ref.read(blocksPrevRowsProvider(seasonId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(blocksListFetchProvider(seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<BlocksView>.error(err, StackTrace.current),
        (rows) =>
            AsyncValue<BlocksView>.data(BlocksView(rows: rows, isStale: false)),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<BlocksView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<BlocksView>.loading(),
    };
  }
}

/// The projection a screen reads (selector).
///
/// Always exposes a usable value: during loading it serves the seeded
/// cached rows; on error it serves the retained snapshot with a stale
/// marker and the error; on success it serves the fresh rows.
@riverpod
BlocksView blocksView(Ref ref, String seasonId) {
  final async = ref.watch(blocksViewControllerProvider(seasonId));
  final prev = ref.watch(blocksPrevRowsProvider(seasonId));
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => BlocksView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => BlocksView(rows: prev, isStale: prev.isNotEmpty),
  };
}

/// Ephemeral optimistic overlay store for the season (controller state, NOT
/// Drift — no global overlay store).
@Riverpod(keepAlive: true)
class BlocksOverlays extends _$BlocksOverlays {
  @override
  List<BlockOverlay> build(String seasonId) => const [];

  void add(BlockOverlay overlay) => state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void dropProjectedIds(Set<String> projectedIds) =>
      state = overlayDropProjectedIds(state, projectedIds);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}

/// Last command failure per season, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class BlocksCommandError extends _$BlocksCommandError {
  @override
  ProblemError? build(String seasonId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Family `BlocksController(seasonId)` on the shared reconciliation runner
/// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
/// staleness, optimistic overlays, dismissible command error.
@Riverpod(keepAlive: true)
class BlocksController extends _$BlocksController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((b) => b.id).toList();
        },
        hasOverlays: () =>
            ref.read(blocksOverlaysProvider(seasonId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(blocksOverlaysProvider(seasonId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(blocksOverlaysProvider(seasonId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(blocksOverlaysProvider(seasonId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  BlocksScreenState build(String seasonId) {
    final async = ref.watch(blocksViewControllerProvider(seasonId));
    final view = ref.watch(blocksViewProvider(seasonId));
    // AsyncValue<BlocksView> → AsyncValue<List<BlockView>>: rows ride on
    // success, the error / loading state is preserved on failure. Retained
    // rows stay available via `cachedRows`.
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<BlockView>>.data(value.rows),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<BlockView>>.error(error, stackTrace),
      _ => const AsyncValue<List<BlockView>>.loading(),
    };
    return BlocksScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(blocksOverlaysProvider(seasonId)),
      commandError: ref.watch(blocksCommandErrorProvider(seasonId)),
    );
  }

  /// Submits the Create Block command. Ids come from the `SeasonView` read
  /// DTO the user acted on (CQRS boundary).
  ///
  /// The optimistic overlay is inserted only after the 2xx and reconciled
  /// in the background; the call returns as soon as the command acked.
  ///
  /// AUTHZ-GATE: the backend create handler is `CurrentUser`-gated
  /// (auth-only). The client mirrors that gate — no network call is issued
  /// without an authenticated session.
  Future<Result<IdVersionResponse>> create({
    required SeasonView season,
    required int number,
    Date? startDate,
    Date? endDate,
  }) async {
    // AUTHZ-GATE: authenticated session required (mirrors the
    // server-side `CurrentUser` gate); deny before any network call.
    // Awaited (not read): a pending restore must resolve before the gate
    // decision, never be treated as denial-by-absence.
    final resolved = await _resolveSession();
    if (resolved == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to create blocks',
        status: 403,
      );
      ref.read(blocksCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }

    final repo = ref.read(blockRepositoryProvider);
    final ack = await repo.create(
      CreateBlockRequest(
        (b) => b
          ..seriesId = season.seriesId
          ..seasonId = season.id
          ..number = number
          ..startDate = startDate
          ..endDate = endDate,
      ),
    );

    return ack.match(
      (err) {
        ref.read(blocksCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(blocksCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(blocksOverlaysProvider(seasonId).notifier)
            .add(
              BlockOverlay(
                id: res.id,
                number: number,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        // Fire-and-forget: the UI must not block on projector lag.
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Resolves the session for the AUTHZ-GATE; a restore failure is treated
  /// as no-session (deny) so the gated request is never issued.
  Future<AuthSession?> _resolveSession() async {
    try {
      return await ref.read(authSessionControllerProvider.future);
    } on Object {
      return null;
    }
  }

  /// Bounded-retry reconciliation (shared runner) + pull-to-refresh entry.
  Future<void> reconcile() => _reconcile.reconcile();

  Future<void> refresh() async {
    ref.read(blocksCommandErrorProvider(seasonId).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() =>
      ref.read(blocksCommandErrorProvider(seasonId).notifier).clear();

  Future<List<BlockView>?> _refetchProjection() async {
    ref.invalidate(blocksListFetchProvider(seasonId));
    final res = await ref.read(blocksListFetchProvider(seasonId).future);
    return res.match((_) => null, (rows) => rows);
  }
}
