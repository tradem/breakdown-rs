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
import '../../data/costume_category_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'costume_categories_state.dart';
import 'next_order_key.dart';

part 'costume_categories_controller.g.dart';

/// Costume-category repository: owns network + Drift cache writes.
@riverpod
CostumeCategoryRepository costumeCategoryRepository(Ref ref) =>
    CostumeCategoryRepository(
      ref.watch(apiClientProvider),
      CostumeCategoryCacheDao(ref.watch(cacheDatabaseProvider)),
    );

/// The injected season-scoped list-fetch seam
/// (`GET /v1/seasons/{season_id}/costume-categories`, server
/// `ORDER BY order_key ASC`). Tests override this provider with a fake.
@riverpod
Future<Result<List<CostumeCategoryView>>> costumeCategoriesListFetch(
  Ref ref,
  String seasonId,
) async {
  final repo = ref.watch(costumeCategoryRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.list(
    seasonId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per season (complete projection — archived
/// rows included, so order-key derivation never depends on the render
/// toggle).
@Riverpod(keepAlive: true)
class CostumeCategoriesPrevRows extends _$CostumeCategoriesPrevRows {
  @override
  List<CostumeCategoryView> build(String seasonId) => const [];

  void set(List<CostumeCategoryView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class CostumeCategoriesView {
  const CostumeCategoriesView({
    required this.rows,
    required this.isStale,
    this.error,
  });

  /// Complete season projection (archived rows included).
  final List<CostumeCategoryView> rows;

  /// `true` when the served rows are from an expired cache or a failed
  /// refetch left only stale cached rows.
  final bool isStale;

  /// Non-null when the last fetch failed. Rows are still served (retained
  /// stale rows) so the screen never goes blank on a transient error.
  final ProblemError? error;
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an
/// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
/// the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
/// through [costumeCategoriesViewProvider].
@Riverpod(keepAlive: false)
class CostumeCategoriesViewController
    extends _$CostumeCategoriesViewController {
  @override
  AsyncValue<CostumeCategoriesView> build(String seasonId) {
    final repo = ref.watch(costumeCategoryRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(seasonId))
          .getOrElse((_) => const <CostumeCategoryView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(costumeCategoriesPrevRowsProvider(seasonId)).isEmpty) {
        ref
            .read(costumeCategoriesPrevRowsProvider(seasonId).notifier)
            .set(cached);
      }
    }());

    final fetch = ref.watch(costumeCategoriesListFetchProvider(seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) =>
            AsyncValue<CostumeCategoriesView>.error(err, StackTrace.current),
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
                  .read(costumeCategoriesPrevRowsProvider(seasonId).notifier)
                  .set(rows);
            }),
          );
          return AsyncValue<CostumeCategoriesView>.data(
            CostumeCategoriesView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<CostumeCategoriesView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<CostumeCategoriesView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one season's categories (issue #366).
///
/// Backed by [CostumeCategoryRepository.isCacheStale] (client-only
/// `cachedAt` + the injectable [clockProvider]); a check failure resolves
/// to `false` (fail-closed — the error path still banners a failed
/// refetch).
@riverpod
Future<bool> costumeCategoriesCacheStale(Ref ref, String seasonId) async {
  final repo = ref.watch(costumeCategoryRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(seasonId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
CostumeCategoriesView costumeCategoriesView(Ref ref, String seasonId) {
  final async = ref.watch(costumeCategoriesViewControllerProvider(seasonId));
  final prev = ref.watch(costumeCategoriesPrevRowsProvider(seasonId));
  // TTL-based staleness (issue #366): a fresh cache served while a normal
  // refetch is in flight is NOT stale. Unknown staleness reads as fresh.
  final ttlStale =
      ref.watch(costumeCategoriesCacheStaleProvider(seasonId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => CostumeCategoriesView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => CostumeCategoriesView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).
@Riverpod(keepAlive: true)
class CostumeCategoriesOverlays extends _$CostumeCategoriesOverlays {
  @override
  List<CostumeCategoryOverlay> build(String seasonId) => const [];

  void add(CostumeCategoryOverlay overlay) =>
      state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void dropProjectedIds(Set<String> projectedIds) =>
      state = overlayDropProjectedIds(state, projectedIds);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}

/// Last command failure per season, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class CostumeCategoriesCommandError extends _$CostumeCategoriesCommandError {
  @override
  ProblemError? build(String seasonId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Render-only archived-visibility toggle per season (default off). Held in
/// its own notifier so toggling never triggers a projection refetch — the
/// toggle affects rendering only, never order-key derivation.
@Riverpod(keepAlive: true)
class CostumeCategoriesShowArchived extends _$CostumeCategoriesShowArchived {
  @override
  bool build(String seasonId) => false;

  void toggle() => state = !state;
}

/// `CostumeCategoriesController(seasonId)` on the shared reconciliation
/// runner: create follows the optimistic-overlay pattern; rename echoes the
/// read row's `version` (409 → keyed copy, no silent overwrite); archive
/// reconciles via the bounded refetch.
@Riverpod(keepAlive: true)
class CostumeCategoriesController extends _$CostumeCategoriesController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((c) => c.id).toList();
        },
        hasOverlays: () =>
            ref.read(costumeCategoriesOverlaysProvider(seasonId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(costumeCategoriesOverlaysProvider(seasonId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(costumeCategoriesOverlaysProvider(seasonId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(costumeCategoriesOverlaysProvider(seasonId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  CostumeCategoriesScreenState build(String seasonId) {
    final async = ref.watch(costumeCategoriesViewControllerProvider(seasonId));
    final view = ref.watch(costumeCategoriesViewProvider(seasonId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<CostumeCategoryView>>.data(
        value.rows,
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<CostumeCategoryView>>.error(error, stackTrace),
      _ => const AsyncValue<List<CostumeCategoryView>>.loading(),
    };
    return CostumeCategoriesScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(costumeCategoriesOverlaysProvider(seasonId)),
      commandError: ref.watch(costumeCategoriesCommandErrorProvider(seasonId)),
      showArchived: ref.watch(costumeCategoriesShowArchivedProvider(seasonId)),
    );
  }

  /// Derives the append-after-last order key over the COMPLETE season
  /// projection (archived rows included — the toggle affects rendering
  /// only, never derivation). Reads the latest successful fetch rows,
  /// falling back to the retained snapshot when the fetch failed.
  String deriveNextOrderKey() => nextOrderKey(cachedOrderKeys());

  /// The complete season projection's order keys (archived included).
  ///
  /// Reads through the list-fetch provider (never through this controller
  /// itself — a provider cannot depend on itself), with the retained
  /// snapshot as the error/loading fallback. Acknowledged overlay keys are
  /// included so a second create before reconciliation cannot re-derive
  /// the same append key as the still-unprojected first one.
  List<String> cachedOrderKeys() {
    final fetch = ref.read(costumeCategoriesListFetchProvider(seasonId));
    final rows = switch (fetch) {
      AsyncData(:final value) => value.match(
        (_) => ref.read(costumeCategoriesPrevRowsProvider(seasonId)),
        (rows) => rows,
      ),
      _ => ref.read(costumeCategoriesPrevRowsProvider(seasonId)),
    };
    final overlayKeys = [
      for (final o in ref.read(costumeCategoriesOverlaysProvider(seasonId)))
        if (o.orderKey != null) o.orderKey!,
    ];
    return [for (final c in rows) c.orderKey, ...overlayKeys];
  }

  /// Submits the Create Category command with the derived append order key.
  ///
  /// AUTHZ-GATE: the backend create handler is `CurrentUser`-gated
  /// (auth-only). The client mirrors that gate — no network call is issued
  /// without an authenticated session.
  Future<Result<IdVersionResponse>> create({required String name}) async {
    // AUTHZ-GATE: authenticated session required; deny before any network
    // call. Awaited (not read): a pending restore must resolve first.
    final resolved = await _resolveSession();
    if (resolved == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to create categories',
        status: 403,
      );
      ref
          .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
          .set(error);
      return const Left(error);
    }

    final orderKey = deriveNextOrderKey();
    final repo = ref.read(costumeCategoryRepositoryProvider);
    final ack = await repo.create(
      seasonId,
      CreateCostumeCategoryRequest(
        (b) => b
          ..seasonId = seasonId
          ..name = name
          ..orderKey = orderKey,
      ),
    );

    return ack.match(
      (err) {
        ref
            .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
            .set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref
            .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
            .clear();
        ref
            .read(costumeCategoriesOverlaysProvider(seasonId).notifier)
            .add(
              CostumeCategoryOverlay(
                id: res.id,
                name: name,
                orderKey: orderKey,
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

  /// Renames a category, echoing the `version` of the read row the user
  /// acted on. A 409 surfaces keyed copy ("changed elsewhere — refresh");
  /// the client never retries with a bumped version on its own.
  ///
  /// AUTHZ-GATE: same session gate as every other hierarchy command.
  Future<Result<int>> rename({
    required CostumeCategoryView category,
    required String name,
  }) async {
    // AUTHZ-GATE: deny before the network call without a resolved
    // authenticated session.
    if (await _resolveSession() == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to rename categories',
        status: 403,
      );
      ref
          .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
          .set(error);
      return const Left(error);
    }
    final repo = ref.read(costumeCategoryRepositoryProvider);
    final res = await repo.rename(category.id, category.version, name);
    return res.match(
      (err) {
        ref
            .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
            .set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref
            .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
            .clear();
        // Reconcile via the bounded refetch so the row shows the new name
        // once projected (no fabricated overlay: the command result carries
        // no display fields beyond the new version).
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Archives a category. Success reconciles via the bounded refetch; the
  /// archived toggle reveals the row afterwards.
  ///
  /// AUTHZ-GATE: same session gate as every other hierarchy command.
  Future<Result<int>> archive({required CostumeCategoryView category}) async {
    // AUTHZ-GATE: deny before the network call without a resolved
    // authenticated session.
    if (await _resolveSession() == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to archive categories',
        status: 403,
      );
      ref
          .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
          .set(error);
      return const Left(error);
    }
    final repo = ref.read(costumeCategoryRepositoryProvider);
    final res = await repo.archive(
      category.id,
      VersionRequest((b) => b..version = category.version),
    );
    return res.match(
      (err) {
        ref
            .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
            .set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref
            .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
            .clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
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
    ref.read(costumeCategoriesCommandErrorProvider(seasonId).notifier).clear();
    await reconcile();
  }

  void toggleArchivedVisibility() => ref
      .read(costumeCategoriesShowArchivedProvider(seasonId).notifier)
      .toggle();

  void dismissCommandError() => ref
      .read(costumeCategoriesCommandErrorProvider(seasonId).notifier)
      .clear();

  Future<List<CostumeCategoryView>?> _refetchProjection() async {
    ref.invalidate(costumeCategoriesListFetchProvider(seasonId));
    final res = await ref.read(
      costumeCategoriesListFetchProvider(seasonId).future,
    );
    return res.match((_) => null, (rows) => rows);
  }
}
