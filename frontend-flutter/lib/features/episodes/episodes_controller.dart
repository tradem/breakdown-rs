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
import '../../data/cache/cache_generation.dart';
import '../../data/cache/hierarchy_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/episode_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'episodes_state.dart';

part 'episodes_controller.g.dart';

/// Episode repository: owns network + Drift cache writes.
@riverpod
EpisodeRepository episodeRepository(Ref ref) => EpisodeRepository(
  ref.watch(apiClientProvider),
  EpisodeCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected block-scoped list-fetch seam via the server-side filter
/// (`GET /v1/episodes?block_id=…`, backend issue #335, PR #355). Tests
/// override this provider with a fake.
@riverpod
Future<Result<List<EpisodeView>>> episodesListFetch(
  Ref ref,
  String blockId,
  String seasonId,
) async {
  final repo = ref.watch(episodeRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listByBlock(
    blockId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per block.
@Riverpod(keepAlive: true)
class EpisodesPrevRows extends _$EpisodesPrevRows {
  @override
  List<EpisodeView> build(String blockId, String seasonId) => const [];

  void set(List<EpisodeView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class EpisodesView {
  const EpisodesView({required this.rows, required this.isStale, this.error});

  final List<EpisodeView> rows;

  /// `true` when the served rows are from an expired cache or a failed
  /// refetch left only stale cached rows.
  final bool isStale;

  /// Non-null when the last fetch failed. Rows are still served (retained
  /// stale rows) so the screen never goes blank on a transient error.
  final ProblemError? error;
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
/// [episodesViewProvider].
@Riverpod(keepAlive: false)
class EpisodesViewController extends _$EpisodesViewController {
  @override
  AsyncValue<EpisodesView> build(String blockId, String seasonId) {
    final repo = ref.watch(episodeRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(blockId))
          .getOrElse((_) => const <EpisodeView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(episodesPrevRowsProvider(blockId, seasonId)).isEmpty) {
        ref
            .read(episodesPrevRowsProvider(blockId, seasonId).notifier)
            .set(cached);
      }
    }());

    final fetch = ref.watch(episodesListFetchProvider(blockId, seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<EpisodesView>.error(err, StackTrace.current),
        (rows) {
          // Converge the retained snapshot with every successful snapshot
          // (including empty ones): a later loading/error state must serve
          // the latest projection, never resurrected deleted rows. Deferred
          // microtask, never a synchronous set during build; this seeder
          // does not watch prevRows, so its own write cannot loop back.
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref
                  .read(episodesPrevRowsProvider(blockId, seasonId).notifier)
                  .set(rows);
            }),
          );
          return AsyncValue<EpisodesView>.data(
            EpisodesView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<EpisodesView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<EpisodesView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one block's episodes (issue #366).
///
/// Backed by [EpisodeRepository.isCacheStale] (client-only `cachedAt` + the
/// injectable [clockProvider]); a check failure resolves to `false`
/// (fail-closed — the error path still banners a failed refetch).
@riverpod
Future<bool> episodesCacheStale(Ref ref, String blockId) async {
  final repo = ref.watch(episodeRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(blockId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
EpisodesView episodesView(Ref ref, String blockId, String seasonId) {
  final async = ref.watch(episodesViewControllerProvider(blockId, seasonId));
  final prev = ref.watch(episodesPrevRowsProvider(blockId, seasonId));
  // TTL-based staleness (issue #366): a fresh cache served while a normal
  // refetch is in flight is NOT stale. Unknown staleness reads as fresh.
  final ttlStale =
      ref.watch(episodesCacheStaleProvider(blockId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => EpisodesView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => EpisodesView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral optimistic overlay store per block (controller state, NOT
/// Drift — no global overlay store).
@Riverpod(keepAlive: true)
class EpisodesOverlays extends _$EpisodesOverlays {
  @override
  List<EpisodeOverlay> build(String blockId, String seasonId) => const [];

  void add(EpisodeOverlay overlay) => state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void dropProjectedIds(Set<String> projectedIds) =>
      state = overlayDropProjectedIds(state, projectedIds);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}

/// Last command failure per block, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class EpisodesCommandError extends _$EpisodesCommandError {
  @override
  ProblemError? build(String blockId, String seasonId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// `EpisodesController(blockId, seasonId)` on the shared reconciliation
/// runner: the `blockId` is the fetch scope (server-side `?block_id=`
/// filter, D3); the `seasonId` namespaces the family by season context.
/// `groupByBlock` stays available as a pure mapper for merged renders.
@Riverpod(keepAlive: true)
class EpisodesController extends _$EpisodesController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((e) => e.id).toList();
        },
        hasOverlays: () =>
            ref.read(episodesOverlaysProvider(blockId, seasonId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(episodesOverlaysProvider(blockId, seasonId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(episodesOverlaysProvider(blockId, seasonId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(episodesOverlaysProvider(blockId, seasonId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  EpisodesScreenState build(String blockId, String seasonId) {
    final async = ref.watch(episodesViewControllerProvider(blockId, seasonId));
    final view = ref.watch(episodesViewProvider(blockId, seasonId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<EpisodeView>>.data(value.rows),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<EpisodeView>>.error(error, stackTrace),
      _ => const AsyncValue<List<EpisodeView>>.loading(),
    };
    return EpisodesScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(episodesOverlaysProvider(blockId, seasonId)),
      commandError: ref.watch(episodesCommandErrorProvider(blockId, seasonId)),
    );
  }

  /// Submits the Create Episode command. Ids (`series_id`, `block_id`) come
  /// from the `BlockView` read DTO the user acted on (CQRS boundary).
  ///
  /// AUTHZ-GATE: the backend create handler is `CurrentUser`-gated
  /// (auth-only). The client mirrors that gate — no network call is issued
  /// without an authenticated session.
  Future<Result<IdVersionResponse>> create({
    required BlockView block,
    required int number,
    String? name,
  }) async {
    // AUTHZ-GATE: authenticated session required; deny before any network
    // call. Awaited (not read): a pending restore must resolve first.
    final resolved = await _resolveSession();
    if (resolved == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to create episodes',
        status: 403,
      );
      ref
          .read(episodesCommandErrorProvider(blockId, seasonId).notifier)
          .set(error);
      return const Left(error);
    }

    final repo = ref.read(episodeRepositoryProvider);
    final ack = await repo.create(
      CreateEpisodeRequest(
        (b) => b
          ..seriesId = block.seriesId
          ..blockId = block.id
          ..number = number
          ..name = name,
      ),
    );

    return ack.match(
      (err) {
        ref
            .read(episodesCommandErrorProvider(blockId, seasonId).notifier)
            .set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref
            .read(episodesCommandErrorProvider(blockId, seasonId).notifier)
            .clear();
        ref
            .read(episodesOverlaysProvider(blockId, seasonId).notifier)
            .add(
              EpisodeOverlay(
                id: res.id,
                number: number,
                name: name,
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

  Future<AuthSession?> _resolveSession() async {
    try {
      return await ref.read(authSessionControllerProvider.future);
    } on Object {
      return null;
    }
  }

  Future<void> reconcile() => _reconcile.reconcile();

  Future<void> refresh() async {
    ref.read(episodesCommandErrorProvider(blockId, seasonId).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() => ref
      .read(episodesCommandErrorProvider(blockId, seasonId).notifier)
      .clear();

  Future<List<EpisodeView>?> _refetchProjection() async {
    ref.invalidate(episodesListFetchProvider(blockId, seasonId));
    final res = await ref.read(
      episodesListFetchProvider(blockId, seasonId).future,
    );
    return res.match((_) => null, (rows) => rows);
  }
}
