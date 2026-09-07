// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

import 'dart:async';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/membership_providers.dart';
import '../../auth/membership_gate.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/scene_shoot_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/scene_shoot_repository.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import '../costumes/costumes_controller.dart';
import 'scene_shoots_state.dart';

part 'scene_shoots_controller.g.dart';

/// Scene-shoot repository: owns network + Drift cache writes.
@riverpod
SceneShootRepository sceneShootRepository(Ref ref) => SceneShootRepository(
  ref.watch(apiClientProvider),
  SceneShootCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected day-board list-fetch seam
/// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`; the
/// backend lists by day in `COALESCE(actual_order, planned_order) ASC`).
/// Tests override this provider with a fake.
@riverpod
Future<Result<List<SceneShootView>>> sceneShootsListFetch(
  Ref ref,
  SceneShootDayScope scope,
) async {
  final repo = ref.watch(sceneShootRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listByDay(
    scope.dayId,
    scope.sceneId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per day (server order).
@Riverpod(keepAlive: true)
class SceneShootsPrevRows extends _$SceneShootsPrevRows {
  @override
  List<SceneShootView> build(SceneShootDayScope scope) => const [];

  void set(List<SceneShootView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class SceneShootsView {
  const SceneShootsView({
    required this.rows,
    required this.isStale,
    this.error,
  });

  final List<SceneShootView> rows;
  final bool isStale;
  final ProblemError? error;
}

/// Read-projection controller (seeder watches repository + fetch only).
@Riverpod(keepAlive: false)
class SceneShootsViewController extends _$SceneShootsViewController {
  @override
  AsyncValue<SceneShootsView> build(SceneShootDayScope scope) {
    final repo = ref.watch(sceneShootRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(scope.dayId))
          .getOrElse((_) => const <SceneShootView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(sceneShootsPrevRowsProvider(scope)).isEmpty) {
        ref.read(sceneShootsPrevRowsProvider(scope).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(sceneShootsListFetchProvider(scope));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<SceneShootsView>.error(err, StackTrace.current),
        (rows) {
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref.read(sceneShootsPrevRowsProvider(scope).notifier).set(rows);
            }),
          );
          return AsyncValue<SceneShootsView>.data(
            SceneShootsView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<SceneShootsView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<SceneShootsView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one day's shoots (issue #366).
@riverpod
Future<bool> sceneShootsCacheStale(Ref ref, SceneShootDayScope scope) async {
  final repo = ref.watch(sceneShootRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(scope.dayId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
SceneShootsView sceneShootsView(Ref ref, SceneShootDayScope scope) {
  final async = ref.watch(sceneShootsViewControllerProvider(scope));
  final prev = ref.watch(sceneShootsPrevRowsProvider(scope));
  final ttlStale =
      ref.watch(sceneShootsCacheStaleProvider(scope)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => SceneShootsView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => SceneShootsView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral row-level optimistic overlays per day (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).
@Riverpod(keepAlive: true)
class SceneShootsOverlays extends _$SceneShootsOverlays {
  @override
  List<SceneShootRowOverlay> build(SceneShootDayScope scope) => const [];

  void add(SceneShootRowOverlay overlay) =>
      state = [...state.where((o) => o.id != overlay.id), overlay];

  void markAllReconciling() => state = [
    for (final o in state) o.copyWithStatus(status: OverlayStatus.reconciling),
  ];

  /// Drops overlays whose version fence the fresh [projection] passes.
  void pruneWithProjection(List<SceneShootView> projection) {
    final byId = {for (final s in projection) s.id: s};
    state = state.where((o) {
      final row = byId[o.id];
      // Create-path overlays (id absent) clear once the id projects.
      if (row == null) return true;
      return !shouldClearSceneShootOverlay(
        projection: row,
        acknowledgedVersion: o.acknowledgedVersion,
      );
    }).toList();
  }

  void dropProjectedIds(Set<String> projectedIds) {
    // Id-based drops never apply to row-level edits (same id before and
    // after); the fence in [pruneWithProjection] owns clearing. Create-path
    // overlays are pruned there too once the projection carries the id
    // with a satisfying version.
  }

  void markAllStale(String warning) => state = [
    for (final o in state)
      o.copyWithStatus(status: OverlayStatus.stale, warning: warning),
  ];
}

/// Last command failure per day, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class SceneShootsCommandError extends _$SceneShootsCommandError {
  @override
  ProblemError? build(SceneShootDayScope scope) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Localized client-side copy for scene-shoot command failures, keyed on
/// the stable problem `code` (never the server's localized `detail`).
String sceneShootErrorCopy(ProblemError error) => switch (error.code) {
  'concurrency.conflict' || 'scene_shoot.version_conflict' =>
    'Changed elsewhere — refresh and try again.',
  'photo.forbidden' ||
  'authz.denied' => 'You need an active costume role in this season.',
  'membership.pending' =>
    'Could not verify permissions — check the connection and retry.',
  'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the change was not saved. Try again.',
  _ => 'The scene shoot could not be saved (${error.code}).',
};

/// `SceneShootsController(scope)` on the shared reconciliation runner:
/// plan derives no client ids (path-authoritative); execution commands
/// echo the acted-on row's `version`; continuity link/list/unlink run the
/// `upload_continuity_photos` capability gate first.
@Riverpod(keepAlive: true)
class SceneShootsController extends _$SceneShootsController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((d) => d.id).toList();
        },
        hasOverlays: () =>
            ref.read(sceneShootsOverlaysProvider(scope)).isNotEmpty,
        markAllReconciling: () => ref
            .read(sceneShootsOverlaysProvider(scope).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(sceneShootsOverlaysProvider(scope).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(sceneShootsOverlaysProvider(scope).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  SceneShootsScreenState build(SceneShootDayScope scope) {
    final async = ref.watch(sceneShootsViewControllerProvider(scope));
    final view = ref.watch(sceneShootsViewProvider(scope));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<SceneShootView>>.data(
        value.rows,
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<SceneShootView>>.error(error, stackTrace),
      _ => const AsyncValue<List<SceneShootView>>.loading(),
    };
    return SceneShootsScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(sceneShootsOverlaysProvider(scope)),
      commandError: ref.watch(sceneShootsCommandErrorProvider(scope)),
    );
  }

  /// Plans a scene shoot on this day (`POST .../scene-shoots`, body
  /// `{ planned_order }` — day/scene travel in the path only, #346).
  Future<Result<IdVersionResponse>> plan({required String plannedOrder}) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      return _denySession();
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final ack = await repo.plan(
      scope.dayId,
      scope.sceneId,
      buildPlanSceneShootRequest(plannedOrder: plannedOrder),
    );
    return ack.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Starts a shoot (version echo from the acted-on row; 409 → keyed copy,
  /// no auto-retry). Optimistic-after-2xx, cleared by the version fence.
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> start({required SceneShootView shoot}) => _execute(
    shoot: shoot,
    call: (repo) => repo.start(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildStartSceneShootRequest(version: shoot.version),
    ),
    optimistic: (row) => applyStartOptimistic(row),
  );

  /// Sets the actual execution order (version echo). Mirrors [start].
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> setActualOrder({
    required SceneShootView shoot,
    required String actualOrder,
  }) => _execute(
    shoot: shoot,
    call: (repo) => repo.setActualOrder(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildSetActualOrderRequest(
        actualOrder: actualOrder,
        version: shoot.version,
      ),
    ),
    optimistic: (row) => applyActualOrderOptimistic(row, actualOrder),
  );

  /// Finishes a started shoot (version echo). Mirrors [start].
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> finish({required SceneShootView shoot}) => _execute(
    shoot: shoot,
    call: (repo) => repo.finish(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildFinishSceneShootRequest(version: shoot.version),
    ),
    optimistic: (row) => applyFinishOptimistic(row),
  );

  /// Skips a shoot (version echo). Mirrors [start].
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> skip({required SceneShootView shoot}) => _execute(
    shoot: shoot,
    call: (repo) => repo.skip(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildSkipSceneShootRequest(version: shoot.version),
    ),
    optimistic: (row) => applySkipOptimistic(row),
  );

  /// Replans a shoot's planned position (version echo). Mirrors [start].
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> replan({
    required SceneShootView shoot,
    required String plannedOrder,
  }) => _execute(
    shoot: shoot,
    call: (repo) => repo.replan(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildReplanSceneShootRequest(
        plannedOrder: plannedOrder,
        version: shoot.version,
      ),
    ),
    optimistic: (row) => applyReplanOptimistic(row, plannedOrder),
  );

  /// Adds a free-text note to the shoot. The request carries no client id
  /// (the backend assigns a UUIDv7 when `note_id` is absent); the
  /// optimistic placeholder rides a pending id until the projection
  /// reconciles the server id.
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> addNote({
    required SceneShootView shoot,
    required String body,
  }) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      return _denySession();
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final res = await repo.addNote(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildAddSceneShootNoteRequest(body: body),
    );
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        ref
            .read(sceneShootsOverlaysProvider(scope).notifier)
            .add(
              SceneShootRowOverlay(
                id: shoot.id,
                overlay: applyAddNoteOptimistic(
                  shoot,
                  optimisticNotePlaceholder(
                    pendingId: 'pending-note-$version',
                    body: body,
                  ),
                ).rebuild((b) => b..version = version),
                acknowledgedVersion: version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Updates a note's body (note id + aggregate version echo). Mirrors
  /// [addNote] with an in-place optimistic body swap.
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> updateNote({
    required SceneShootView shoot,
    required String noteId,
    required String body,
  }) => _execute(
    shoot: shoot,
    call: (repo) => repo.updateNote(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      noteId,
      buildUpdateSceneShootNoteRequest(body: body, version: shoot.version),
    ),
    optimistic: (row) => applyUpdateNoteOptimistic(row, noteId, body),
  );

  /// Removes a note (note id in path, version echo in query). Mirrors
  /// [addNote] with an optimistic removal (the UI confirms first).
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> removeNote({
    required SceneShootView shoot,
    required String noteId,
  }) => _execute(
    shoot: shoot,
    call: (repo) => repo.removeNote(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      noteId,
      buildSceneShootNoteRemoveRequest(version: shoot.version),
    ),
    optimistic: (row) => applyRemoveNoteOptimistic(row, noteId),
  );

  /// Shared execution-command runner: session gate → version-echoed call →
  /// optimistic-after-2xx overlay (ack version) + bounded reconciliation.
  Future<Result<int>> _execute({
    required SceneShootView shoot,
    required Future<Result<int>> Function(SceneShootRepository repo) call,
    required SceneShootView Function(SceneShootView row) optimistic,
  }) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      return _denySession();
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final res = await call(repo);
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        ref
            .read(sceneShootsOverlaysProvider(scope).notifier)
            .add(
              SceneShootRowOverlay(
                id: shoot.id,
                // The overlay version advances to the ack: a follow-up
                // command echoes it instead of the pre-command version
                // (which the server would reject as a version conflict).
                overlay: optimistic(shoot).rebuild((b) => b..version = version),
                acknowledgedVersion: version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Wraps the shooting day (`POST /v1/shooting-days/{id}/wrap` — guarded
  /// day-level action; the UI confirms with the finality copy first, D3).
  ///
  /// // AUTHZ-GATE: authenticated session required before the call.
  Future<Result<int>> wrap({required int dayVersion}) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      return _denySession();
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final res = await repo.wrap(
      scope.dayId,
      buildWrapShootingDayRequest(version: dayVersion),
    );
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Links an uploaded photo to the shoot (version echo). The photo bytes
  /// upload itself reuses the Phase 2 capture pipeline
  /// ([PhotoRepository.upload]); this call only binds the acknowledged
  /// photo id to the scene-shoot context.
  ///
  /// // AUTHZ-GATE: `upload_continuity_photos` capability checked before
  /// the call (_UPLOAD, LIST, and UNLINK share this gate_).
  Future<Result<int>> linkContinuityPhoto({
    required SceneShootView shoot,
    required String photoId,
  }) async {
    // AUTHZ-GATE: continuity capability checked before any network call.
    final gate = await _continuityGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final res = await repo.linkContinuityPhoto(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      buildLinkContinuityPhotoRequest(photoId: photoId, version: shoot.version),
    );
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Lists the shoot's continuity photo ids.
  ///
  /// // AUTHZ-GATE: same capability as upload/unlink — a member who may
  /// not manage continuity photos must not enumerate them.
  Future<Result<List<String>>> listContinuityPhotos({
    required SceneShootView shoot,
  }) async {
    // AUTHZ-GATE: continuity capability checked before any network call.
    final gate = await _continuityGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final res = await repo.listContinuityPhotos(
      scope.dayId,
      scope.sceneId,
      shoot.id,
    );
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, List<String>>(err);
      },
      (ids) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        return Right<ProblemError, List<String>>(ids);
      },
    );
  }

  /// Unlinks a continuity photo (confirm-first in the UI; version echo).
  ///
  /// // AUTHZ-GATE: `upload_continuity_photos` capability checked before
  /// the call.
  Future<Result<int>> unlinkContinuityPhoto({
    required SceneShootView shoot,
    required String photoId,
  }) async {
    // AUTHZ-GATE: continuity capability checked before any network call.
    final gate = await _continuityGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(sceneShootRepositoryProvider);
    final res = await repo.unlinkContinuityPhoto(
      scope.dayId,
      scope.sceneId,
      shoot.id,
      photoId,
      shoot.version,
    );
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Uploads prepared continuity bytes to a season costume (raw bytes,
  /// content-type header) and returns the acknowledged photo for linking.
  /// The photo lives on the costume (bytes are costume-scoped); the
  /// caller binds it to the shoot via [linkContinuityPhoto]. The board
  /// reconciles through the link's refresh.
  ///
  /// // AUTHZ-GATE: `upload_continuity_photos` capability checked before
  /// the call — same gate as link/list/unlink.
  Future<Result<PhotoView>> uploadContinuityBytes({
    required String costumeId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    // AUTHZ-GATE: continuity capability checked before any network call.
    final gate = await _continuityGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(costumePhotoRepositoryProvider);
    final res = await repo.upload(costumeId, bytes, contentType);
    return res.match(
      (err) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(err);
        return Left<ProblemError, PhotoView>(err);
      },
      (view) {
        ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
        return Right<ProblemError, PhotoView>(view);
      },
    );
  }

  /// Client-side AUTHZ-GATE for continuity commands (link/list/unlink):
  /// the `upload_continuity_photos` capability is checked BEFORE any
  /// network call. A denial short-circuits with the localized 403
  /// narrative and never issues the request (provable by a fake repo call
  /// count of zero).
  Future<GateDecision> _continuityGate() async {
    final session = await _resolveSession();
    if (session == null) return const GateDeny('auth.session_required');
    GateDecision gate;
    try {
      final res = await ref.read(
        membershipFetchProvider(scope.seasonId).future,
      );
      gate = res.match(
        (_) => const GateDeny('membership.pending'),
        (dto) => checkPhotoCapability(dto),
      );
    } on Object {
      gate = const GateDeny('membership.pending');
    }
    return gate;
  }

  GateDecision? _deny(GateDecision gate) {
    if (gate is GateDeny) {
      final error = ProblemError(code: gate.code, status: 403);
      ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(error);
      return gate;
    }
    return null;
  }

  /// Session denial shared by the execution commands (non-continuity).
  Left<ProblemError, T> _denySession<T>() {
    const error = ProblemError(code: 'auth.session_required', status: 403);
    ref.read(sceneShootsCommandErrorProvider(scope).notifier).set(error);
    return const Left(error);
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
    ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() =>
      ref.read(sceneShootsCommandErrorProvider(scope).notifier).clear();

  Future<List<SceneShootView>?> _refetchProjection() async {
    ref.invalidate(sceneShootsListFetchProvider(scope));
    ref.invalidate(sceneShootsCacheStaleProvider(scope));
    final res = await ref.read(sceneShootsListFetchProvider(scope).future);
    return res.match((_) => null, (rows) {
      // The version fence owns overlay clearing: prune against the fresh
      // projection here so a stale row never restores pre-command state.
      if (ref.mounted) {
        ref
            .read(sceneShootsOverlaysProvider(scope).notifier)
            .pruneWithProjection(rows);
      }
      return rows;
    });
  }
}
