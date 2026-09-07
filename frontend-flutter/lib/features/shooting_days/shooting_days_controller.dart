// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/costume_domains_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/shooting_day_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import '../costume_categories/next_order_key.dart';
import 'shooting_days_state.dart';

part 'shooting_days_controller.g.dart';

/// Shooting-day repository: owns network + Drift cache writes.
@riverpod
ShootingDayRepository shootingDayRepository(Ref ref) => ShootingDayRepository(
  ref.watch(apiClientProvider),
  ShootingDayCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/episodes/{episode_id}/shooting-days`, server `order_key ASC`).
/// Tests override this provider with a fake.
@riverpod
Future<Result<List<ShootingDayView>>> shootingDaysListFetch(
  Ref ref,
  String episodeId,
) async {
  final repo = ref.watch(shootingDayRepositoryProvider);
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

/// Retained last-good snapshot per episode (server order).
@Riverpod(keepAlive: true)
class ShootingDaysPrevRows extends _$ShootingDaysPrevRows {
  @override
  List<ShootingDayView> build(String episodeId) => const [];

  void set(List<ShootingDayView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class ShootingDaysView {
  const ShootingDaysView({
    required this.rows,
    required this.isStale,
    this.error,
  });

  final List<ShootingDayView> rows;
  final bool isStale;
  final ProblemError? error;
}

/// Read-projection controller (seeder watches repository + fetch only).
@Riverpod(keepAlive: false)
class ShootingDaysViewController extends _$ShootingDaysViewController {
  @override
  AsyncValue<ShootingDaysView> build(String episodeId) {
    final repo = ref.watch(shootingDayRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(episodeId))
          .getOrElse((_) => const <ShootingDayView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(shootingDaysPrevRowsProvider(episodeId)).isEmpty) {
        ref.read(shootingDaysPrevRowsProvider(episodeId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(shootingDaysListFetchProvider(episodeId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<ShootingDaysView>.error(err, StackTrace.current),
        (rows) {
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref
                  .read(shootingDaysPrevRowsProvider(episodeId).notifier)
                  .set(rows);
            }),
          );
          return AsyncValue<ShootingDaysView>.data(
            ShootingDaysView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<ShootingDaysView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<ShootingDaysView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one episode's days (issue #366).
@riverpod
Future<bool> shootingDaysCacheStale(Ref ref, String episodeId) async {
  final repo = ref.watch(shootingDayRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(episodeId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
ShootingDaysView shootingDaysView(Ref ref, String episodeId) {
  final async = ref.watch(shootingDaysViewControllerProvider(episodeId));
  final prev = ref.watch(shootingDaysPrevRowsProvider(episodeId));
  final ttlStale =
      ref.watch(shootingDaysCacheStaleProvider(episodeId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => ShootingDaysView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => ShootingDaysView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).
@Riverpod(keepAlive: true)
class ShootingDaysOverlays extends _$ShootingDaysOverlays {
  @override
  List<ShootingDayOverlay> build(String episodeId) => const [];

  void add(ShootingDayOverlay overlay) => state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void dropProjectedIds(Set<String> projectedIds) =>
      state = overlayDropProjectedIds(state, projectedIds);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}

/// Last command failure per episode, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class ShootingDaysCommandError extends _$ShootingDaysCommandError {
  @override
  ProblemError? build(String episodeId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Localized client-side copy for shooting-day command failures, keyed on
/// the stable problem `code` (never the server's localized `detail`).
String shootingDayErrorCopy(ProblemError error) => switch (error.code) {
  'concurrency.conflict' || 'shooting_day.version_conflict' =>
    'Changed elsewhere — refresh and try again.',
  'authz.denied' || 'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the change was not saved. Try again.',
  _ => 'The shooting day could not be saved (${error.code}).',
};

/// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
/// create derives the append `order_key` with the shared rule (`source:
/// Manual`); updates are single-intent (reorder / reschedule+unschedule /
/// rename — one PATCH per action); archive reconciles via the bounded
/// refetch.
@Riverpod(keepAlive: true)
class ShootingDaysController extends _$ShootingDaysController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((d) => d.id).toList();
        },
        hasOverlays: () =>
            ref.read(shootingDaysOverlaysProvider(episodeId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(shootingDaysOverlaysProvider(episodeId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(shootingDaysOverlaysProvider(episodeId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(shootingDaysOverlaysProvider(episodeId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  ShootingDaysScreenState build(String episodeId) {
    final async = ref.watch(shootingDaysViewControllerProvider(episodeId));
    final view = ref.watch(shootingDaysViewProvider(episodeId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<ShootingDayView>>.data(
        value.rows,
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<ShootingDayView>>.error(error, stackTrace),
      _ => const AsyncValue<List<ShootingDayView>>.loading(),
    };
    return ShootingDaysScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(shootingDaysOverlaysProvider(episodeId)),
      commandError: ref.watch(shootingDaysCommandErrorProvider(episodeId)),
    );
  }

  /// Derives the append-after-last order key over the episode projection
  /// (shared pure function — the same append rule as Phase 1).
  String deriveNextOrderKey() {
    final fetch = ref.read(shootingDaysListFetchProvider(episodeId));
    final rows = switch (fetch) {
      AsyncData(:final value) => value.match(
        (_) => ref.read(shootingDaysPrevRowsProvider(episodeId)),
        (rows) => rows,
      ),
      _ => ref.read(shootingDaysPrevRowsProvider(episodeId)),
    };
    final overlayKeys = [
      for (final o in ref.read(shootingDaysOverlaysProvider(episodeId)))
        if (o.orderKey != null) o.orderKey!,
    ];
    return nextOrderKey([for (final d in rows) d.orderKey, ...overlayKeys]);
  }

  /// Creates a day (`POST /v1/episodes/{episode_id}/shooting-days` —
  /// derived append `order_key`, `Manual` source, optional label/date).
  Future<Result<IdVersionResponse>> create({String? label, Date? date}) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(error);
      return const Left(error);
    }
    final orderKey = deriveNextOrderKey();
    final repo = ref.read(shootingDayRepositoryProvider);
    final ack = await repo.create(
      episodeId,
      CreateShootingDayRequest(
        (b) => b
          ..episodeId = episodeId
          ..orderKey = orderKey
          ..source_.replace(
            ShootingDaySource(
              (s) => s..oneOf = OneOf.fromValue1(value: 'Manual'),
            ),
          )
          ..label = label
          ..date = date,
      ),
    );
    return ack.match(
      (err) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();
        ref
            .read(shootingDaysOverlaysProvider(episodeId).notifier)
            .add(
              ShootingDayOverlay(
                id: res.id,
                label: label,
                orderKey: orderKey,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Single-intent reorder (one PATCH with a new key from the read model's
  /// neighbor keys — the UI computes the key, never re-sorts).
  Future<Result<int>> reorder({
    required ShootingDayView day,
    required String orderKey,
  }) => _singleIntent(
    day: day,
    request: buildReorderRequest(orderKey: orderKey, version: day.version),
  );

  /// Single-intent reschedule (date picker).
  Future<Result<int>> reschedule({
    required ShootingDayView day,
    required Date date,
  }) => _singleIntent(
    day: day,
    request: buildRescheduleRequest(date: date, version: day.version),
  );

  /// Single-intent unschedule (`date: null` — explicit clear).
  Future<Result<int>> unschedule({required ShootingDayView day}) =>
      _singleIntent(
        day: day,
        request: buildUnscheduleRequest(version: day.version),
      );

  /// Single-intent rename.
  Future<Result<int>> rename({
    required ShootingDayView day,
    required String? label,
  }) => _singleIntent(
    day: day,
    request: buildRenameRequest(label: label, version: day.version),
  );

  Future<Result<int>> _singleIntent({
    required ShootingDayView day,
    required UpdateShootingDayRequest request,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(shootingDayRepositoryProvider);
    final res = await repo.update(day.id, request);
    return res.match(
      (err) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Archives a day (version echo). Success reconciles via the bounded
  /// refetch.
  Future<Result<int>> archive({required ShootingDayView day}) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(shootingDayRepositoryProvider);
    final res = await repo.archive(
      day.id,
      VersionRequest((b) => b..version = day.version),
    );
    return res.match(
      (err) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Scene scheduling from the scene side (day id from the picked DTO, the
  /// scene `version` from the acted-on `SceneView`).
  Future<Result<int>> scheduleScene({
    required String sceneId,
    required int sceneVersion,
    required String shootingDayId,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(shootingDayRepositoryProvider);
    final res = await repo.scheduleScene(
      sceneId,
      ScheduleSceneRequest(
        (b) => b
          ..shootingDayId = shootingDayId
          ..version = sceneVersion,
      ),
    );
    return res.match(
      (err) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Scene unscheduling (DELETE with `?version=`).
  Future<Result<int>> unscheduleScene({
    required String sceneId,
    required int sceneVersion,
    required String shootingDayId,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(shootingDayRepositoryProvider);
    final res = await repo.unscheduleScene(
      sceneId,
      shootingDayId,
      sceneVersion,
    );
    return res.match(
      (err) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();
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
    ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() =>
      ref.read(shootingDaysCommandErrorProvider(episodeId).notifier).clear();

  Future<List<ShootingDayView>?> _refetchProjection() async {
    ref.invalidate(shootingDaysListFetchProvider(episodeId));
    ref.invalidate(shootingDaysCacheStaleProvider(episodeId));
    final res = await ref.read(shootingDaysListFetchProvider(episodeId).future);
    return res.match((_) => null, (rows) => rows);
  }
}
