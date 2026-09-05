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
import '../../data/scene_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'scenes_state.dart';

part 'scenes_controller.g.dart';

/// Scene repository: owns network + Drift cache writes.
@riverpod
SceneRepository sceneRepository(Ref ref) => SceneRepository(
  ref.watch(apiClientProvider),
  SceneCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/scenes?episode_id=…`). Tests override this provider with a fake.
@riverpod
Future<Result<List<SceneView>>> scenesListFetch(
  Ref ref,
  String episodeId,
) async {
  final repo = ref.watch(sceneRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listByEpisode(
    episodeId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per episode.
@Riverpod(keepAlive: true)
class ScenesPrevRows extends _$ScenesPrevRows {
  @override
  List<SceneView> build(String episodeId) => const [];

  void set(List<SceneView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class ScenesView {
  const ScenesView({required this.rows, required this.isStale, this.error});

  final List<SceneView> rows;

  /// `true` when the served rows are from an expired cache or a failed
  /// refetch left only stale cached rows.
  final bool isStale;

  /// Non-null when the last fetch failed. Rows are still served (retained
  /// stale rows) so the screen never goes blank on a transient error.
  final ProblemError? error;
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
/// [scenesViewProvider].
@Riverpod(keepAlive: false)
class ScenesViewController extends _$ScenesViewController {
  @override
  AsyncValue<ScenesView> build(String episodeId) {
    final repo = ref.watch(sceneRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(episodeId))
          .getOrElse((_) => const <SceneView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(scenesPrevRowsProvider(episodeId)).isEmpty) {
        ref.read(scenesPrevRowsProvider(episodeId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(scenesListFetchProvider(episodeId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<ScenesView>.error(err, StackTrace.current),
        (rows) =>
            AsyncValue<ScenesView>.data(ScenesView(rows: rows, isStale: false)),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<ScenesView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<ScenesView>.loading(),
    };
  }
}

/// The projection a screen reads (selector).
@riverpod
ScenesView scenesView(Ref ref, String episodeId) {
  final async = ref.watch(scenesViewControllerProvider(episodeId));
  final prev = ref.watch(scenesPrevRowsProvider(episodeId));
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => ScenesView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => ScenesView(rows: prev, isStale: prev.isNotEmpty),
  };
}

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).
@Riverpod(keepAlive: true)
class ScenesOverlays extends _$ScenesOverlays {
  @override
  List<SceneOverlay> build(String episodeId) => const [];

  void add(SceneOverlay overlay) => state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void dropProjectedIds(Set<String> projectedIds) =>
      state = overlayDropProjectedIds(state, projectedIds);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}

/// Last command failure per episode, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class ScenesCommandError extends _$ScenesCommandError {
  @override
  ProblemError? build(String episodeId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// `ScenesController(episodeId)` on the shared reconciliation runner.
@Riverpod(keepAlive: true)
class ScenesController extends _$ScenesController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((s) => s.id).toList();
        },
        hasOverlays: () =>
            ref.read(scenesOverlaysProvider(episodeId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(scenesOverlaysProvider(episodeId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(scenesOverlaysProvider(episodeId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(scenesOverlaysProvider(episodeId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  ScenesScreenState build(String episodeId) {
    final async = ref.watch(scenesViewControllerProvider(episodeId));
    final view = ref.watch(scenesViewProvider(episodeId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<SceneView>>.data(value.rows),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<SceneView>>.error(error, stackTrace),
      _ => const AsyncValue<List<SceneView>>.loading(),
    };
    return ScenesScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(scenesOverlaysProvider(episodeId)),
      commandError: ref.watch(scenesCommandErrorProvider(episodeId)),
    );
  }

  /// Submits the Create Scene command (`episode_id` + `details` from the
  /// `EpisodeView` read DTO the user acted on — CQRS boundary).
  ///
  /// AUTHZ-GATE: the backend create handler is `CurrentUser`-gated
  /// (auth-only). The client mirrors that gate — no network call is issued
  /// without an authenticated session.
  Future<Result<IdVersionResponse>> create({
    required EpisodeView episode,
    required SceneDetails details,
  }) async {
    // AUTHZ-GATE: authenticated session required; deny before any network
    // call. Awaited (not read): a pending restore must resolve first.
    final resolved = await _resolveSession();
    if (resolved == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to create scenes',
        status: 403,
      );
      ref.read(scenesCommandErrorProvider(episodeId).notifier).set(error);
      return const Left(error);
    }

    final repo = ref.read(sceneRepositoryProvider);
    final ack = await repo.create(
      CreateSceneRequest(
        (b) => b
          ..episodeId = episode.id
          ..details.replace(details),
      ),
    );

    return ack.match(
      (err) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();
        ref
            .read(scenesOverlaysProvider(episodeId).notifier)
            .add(
              SceneOverlay(
                id: res.id,
                summary: details.summary,
                sceneNumber: details.sceneNumber,
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
    ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() =>
      ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();

  Future<List<SceneView>?> _refetchProjection() async {
    ref.invalidate(scenesListFetchProvider(episodeId));
    final res = await ref.read(scenesListFetchProvider(episodeId).future);
    return res.match((_) => null, (rows) => rows);
  }
}
