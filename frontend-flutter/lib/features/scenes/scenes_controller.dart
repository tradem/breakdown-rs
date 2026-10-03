// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/membership_providers.dart';
import '../../auth/membership_gate.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/hierarchy_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/scene_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import '../../l10n/generated/app_localizations.dart';
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
        (rows) {
          // Converge the retained snapshot with every successful snapshot
          // (including empty ones): a later loading/error state must serve
          // the latest projection, never resurrected deleted rows. Deferred
          // microtask, never a synchronous set during build; this seeder
          // does not watch prevRows, so its own write cannot loop back.
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref.read(scenesPrevRowsProvider(episodeId).notifier).set(rows);
            }),
          );
          return AsyncValue<ScenesView>.data(
            ScenesView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<ScenesView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<ScenesView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one episode's scenes (issue #366).
///
/// Backed by [SceneRepository.isCacheStale] (client-only `cachedAt` + the
/// injectable [clockProvider]); a check failure resolves to `false`
/// (fail-closed — the error path still banners a failed refetch).
@riverpod
Future<bool> scenesCacheStale(Ref ref, String episodeId) async {
  // NOTE (issue #366 review): memoized until invalidated — every refetch
  // path invalidates this alongside the list fetch (see _refetchProjection).
  final repo = ref.watch(sceneRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(episodeId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
ScenesView scenesView(Ref ref, String episodeId) {
  final async = ref.watch(scenesViewControllerProvider(episodeId));
  final prev = ref.watch(scenesPrevRowsProvider(episodeId));
  // TTL-based staleness (issue #366): a fresh cache served while a normal
  // refetch is in flight is NOT stale. Unknown staleness reads as fresh.
  final ttlStale =
      ref.watch(scenesCacheStaleProvider(episodeId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => ScenesView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => ScenesView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
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

/// Ephemeral optimistic beat-overlay store per episode (issue #546):
/// controller state keyed by SCENE id — never Drift.
@Riverpod(keepAlive: true)
class SceneBeatOverlays extends _$SceneBeatOverlays {
  @override
  List<SceneBeatOverlay> build(String episodeId) => const [];

  void add(SceneBeatOverlay overlay) => state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);

  /// Version-fence drop: an overlay survives until the projected scene row
  /// carries `version >= overlay.version`. A lagging projection NEVER
  /// discards the optimistic render — bounded-retry reconciliation keeps
  /// refetching; exhaustion marks the overlay stale instead (no silent
  /// discard).
  void dropProjected(Map<String, int> projectedVersions) => state = [
    for (final o in state)
      if ((projectedVersions[o.id] ?? -1) < o.version) o,
  ];
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

  /// Scene rows from the latest successful projection refetch (capture for
  /// the version-fence drop below — the drop callback must compare against
  /// the EXACT rows this pass fetched, not a later rebuild's view).
  List<SceneView> _lastProjectedRows = const [];

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          if (rows != null) _lastProjectedRows = rows;
          return rows?.map((s) => s.id).toList();
        },
        hasOverlays: () =>
            ref.read(scenesOverlaysProvider(episodeId)).isNotEmpty ||
            ref.read(sceneBeatOverlaysProvider(episodeId)).isNotEmpty,
        markAllReconciling: () {
          ref
              .read(scenesOverlaysProvider(episodeId).notifier)
              .markAllReconciling();
          ref
              .read(sceneBeatOverlaysProvider(episodeId).notifier)
              .markAllReconciling();
        },
        dropProjectedIds: (ids) {
          ref
              .read(scenesOverlaysProvider(episodeId).notifier)
              .dropProjectedIds(ids);
          // Beat overlays drop ONLY on a version-fenced projection row: an
          // id-presence drop would discard the optimistic beats on a lagging
          // row (pre-ack aggregate version).
          ref.read(sceneBeatOverlaysProvider(episodeId).notifier).dropProjected(
            {for (final s in _lastProjectedRows) s.id: s.version},
          );
        },
        markAllStale: (warning) {
          ref
              .read(scenesOverlaysProvider(episodeId).notifier)
              .markAllStale(warning);
          ref
              .read(sceneBeatOverlaysProvider(episodeId).notifier)
              .markAllStale(warning);
        },
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
    final beatOverlays = ref.watch(sceneBeatOverlaysProvider(episodeId));
    return ScenesScreenState(
      projected: projected,
      cachedRows: _applyBeatOverlays(view.rows, beatOverlays),
      isStale: view.isStale,
      overlays: ref.watch(scenesOverlaysProvider(episodeId)),
      beatOverlays: beatOverlays,
      commandError: ref.watch(scenesCommandErrorProvider(episodeId)),
    );
  }

  /// Merges optimistic beat overlays into the served scene rows: while the
  /// projection row lags the ack (`row.version < overlay.version`), the
  /// row renders the overlay's beat list at the acked version. Once the
  /// projection catches up, the overlay is dropped by the reconciliation
  /// pass and the projected row wins.
  List<SceneView> _applyBeatOverlays(
    List<SceneView> rows,
    List<SceneBeatOverlay> overlays,
  ) {
    if (overlays.isEmpty) return rows;
    final bySceneId = {for (final o in overlays) o.id: o};
    return [
      for (final row in rows)
        switch (bySceneId[row.id]) {
          final overlay? when row.version < overlay.version => overlay.applyTo(
            row,
          ),
          _ => row,
        },
    ];
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

  /// Client-side AUTHZ-GATE for scene costume-beat commands (issue #546):
  /// the backend classifies these routes under the same season-scoped
  /// costume-assign story as the costume-assign surface — the client
  /// mirrors `checkAssignCapability` BEFORE any network call. A denial
  /// short-circuits with the localized 403 narrative and never issues the
  /// request (provable by a fake repo call count of zero).
  Future<GateDecision> _beatGate(String seasonId) async {
    final session = await _resolveSession();
    if (session == null) return const GateDeny('auth.session_required');
    GateDecision gate;
    try {
      final res = await ref.read(membershipFetchProvider(seasonId).future);
      gate = res.match(
        (_) => const GateDeny('membership.pending') as GateDecision,
        (dto) => checkAssignCapability(dto),
      );
    } on Object {
      gate = const GateDeny('membership.pending');
    }
    return gate;
  }

  /// Denies with a 403 problem keyed on the gate code, or returns `null`
  /// to proceed.
  ProblemError? _beatDeny(GateDecision gate) {
    if (gate is GateDeny) {
      final error = ProblemError(code: gate.code, status: 403);
      ref.read(scenesCommandErrorProvider(episodeId).notifier).set(error);
      return error;
    }
    return null;
  }

  /// Resolves the freshest scene version at command time (version fence,
  /// mirrors the costume controller's `_resolveVersion`): a write must echo
  /// the version the server aggregate currently holds — NEVER the
  /// screen-captured snapshot, which can lag the acknowledged state.
  /// Sources, freshest known first: this client's beat-overlay ack, the
  /// reconciled projection row, the screen-passed fallback.
  int _resolveSceneVersion(String sceneId, int fallback) {
    var version = fallback;
    for (final o in ref.read(sceneBeatOverlaysProvider(episodeId))) {
      if (o.id == sceneId && o.version > version) version = o.version;
    }
    for (final row in ref.read(scenesViewProvider(episodeId)).rows) {
      if (row.id == sceneId && row.version > version) version = row.version;
    }
    return version;
  }

  /// The freshest known beat list for [scene] at command time: the
  /// acted-on snapshot can lag BOTH the projected row (a reconcile refetch
  /// landed after the screen rendered) and this client's own beat overlay
  /// (a second command acks while the first is still unprojected —
  /// `overlayAdd` replaces the per-scene entry, so building from a stale
  /// list would DROP earlier acknowledged beats). Sources, freshest first;
  /// on a version tie the projected row wins (same tie-break as the
  /// version-fenced overlay drop):
  ///   1. the matching projected row (`scenesViewProvider`),
  ///   2. the matching beat overlay (`sceneBeatOverlaysProvider`),
  ///   3. the screen-passed [scene] snapshot.
  List<SceneCostumeBeatView> _currentBeats(SceneView scene) {
    var version = scene.version;
    var beats = scene.costumeBeats?.toList() ?? const <SceneCostumeBeatView>[];
    final projected = ref
        .read(scenesViewProvider(episodeId))
        .rows
        .where((row) => row.id == scene.id)
        .firstOrNull;
    if (projected != null && projected.version > version) {
      version = projected.version;
      beats =
          projected.costumeBeats?.toList() ?? const <SceneCostumeBeatView>[];
    }
    final overlay = ref
        .read(sceneBeatOverlaysProvider(episodeId))
        .where((o) => o.id == scene.id)
        .firstOrNull;
    if (overlay != null && overlay.version > version) {
      return overlay.beats.toList();
    }
    return beats;
  }

  /// Adds a costume beat (issue #546). The aggregate computes the dense
  /// zero-based order; the optimistic overlay appends at the next index
  /// for the character (display-only until the projection reconciles).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call — the backend routes ride the same season-scoped costume story.
  Future<Result<int>> addCostumeBeat({
    required String seasonId,
    required SceneView scene,
    required String characterId,
    required String costumeId,
    String? note,
    String? characterName,
    String? costumeCategoryName,
  }) async {
    final deny = _beatDeny(await _beatGate(seasonId));
    if (deny != null) return Left(deny);
    final repo = ref.read(sceneRepositoryProvider);
    final res = await repo.addCostumeBeat(
      scene.id,
      AddSceneCostumeBeatRequest(
        (b) => b
          ..characterId = characterId
          ..costumeId = costumeId
          ..note = note
          ..version = _resolveSceneVersion(scene.id, scene.version),
      ),
    );
    return res.match(
      (err) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();
        final current = _currentBeats(scene);
        // The aggregate computes the dense zero-based position as
        // max(existing orders)+1 — NEVER a count: after a removal the
        // surviving orders keep their positions ([0, 2] stays [0, 2]), so
        // a count-based order would collide with the persisted one.
        final nextOrder =
            current
                .where((b) => b.characterId == characterId)
                .map((b) => b.order)
                .fold<int>(
                  -1,
                  (maxOrder, order) => order > maxOrder ? order : maxOrder,
                ) +
            1;
        final beat = SceneCostumeBeatView(
          (b) => b
            ..characterId = characterId
            ..characterName = characterName
            ..costumeId = costumeId
            ..costumeCategoryName = costumeCategoryName
            ..order = nextOrder
            ..note = note,
        );
        ref
            .read(sceneBeatOverlaysProvider(episodeId).notifier)
            .add(
              SceneBeatOverlay(
                id: scene.id,
                version: version,
                beats: [...current, beat],
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Updates a costume beat's costume/note (`PATCH`).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call.
  Future<Result<int>> updateCostumeBeat({
    required String seasonId,
    required SceneView scene,
    required String characterId,
    required int order,
    required String costumeId,
    String? note,
    String? costumeCategoryName,
  }) async {
    final deny = _beatDeny(await _beatGate(seasonId));
    if (deny != null) return Left(deny);
    final repo = ref.read(sceneRepositoryProvider);
    final res = await repo.updateCostumeBeat(
      scene.id,
      characterId,
      order,
      UpdateSceneCostumeBeatRequest(
        (b) => b
          ..costumeId = costumeId
          ..note = note
          ..version = _resolveSceneVersion(scene.id, scene.version),
      ),
    );
    return res.match(
      (err) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();
        final current = _currentBeats(scene);
        final beats = [
          for (final beat in current)
            if (beat.characterId == characterId && beat.order == order)
              SceneCostumeBeatView(
                (b) => b
                  ..characterId = characterId
                  ..characterName = beat.characterName
                  ..costumeId = costumeId
                  ..costumeCategoryName = costumeCategoryName
                  ..order = order
                  ..note = note,
              )
            else
              beat,
        ];
        ref
            .read(sceneBeatOverlaysProvider(episodeId).notifier)
            .add(
              SceneBeatOverlay(
                id: scene.id,
                version: version,
                beats: beats,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Removes one costume beat (`DELETE …/{order}`).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call.
  Future<Result<int>> removeCostumeBeat({
    required String seasonId,
    required SceneView scene,
    required String characterId,
    required int order,
  }) async {
    final deny = _beatDeny(await _beatGate(seasonId));
    if (deny != null) return Left(deny);
    final repo = ref.read(sceneRepositoryProvider);
    final res = await repo.removeCostumeBeat(
      scene.id,
      characterId,
      order,
      _resolveSceneVersion(scene.id, scene.version),
    );
    return res.match(
      (err) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();
        ref
            .read(sceneBeatOverlaysProvider(episodeId).notifier)
            .add(
              SceneBeatOverlay(
                id: scene.id,
                version: version,
                beats: [
                  for (final beat in _currentBeats(scene))
                    if (beat.characterId != characterId || beat.order != order)
                      beat,
                ],
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Clears ALL costume beats of a character
  /// (`DELETE …/costumes/{character_id}` = "no costume in this scene").
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call.
  Future<Result<int>> clearCostumeBeats({
    required String seasonId,
    required SceneView scene,
    required String characterId,
  }) async {
    final deny = _beatDeny(await _beatGate(seasonId));
    if (deny != null) return Left(deny);
    final repo = ref.read(sceneRepositoryProvider);
    final res = await repo.clearCostumeBeats(
      scene.id,
      characterId,
      _resolveSceneVersion(scene.id, scene.version),
    );
    return res.match(
      (err) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(scenesCommandErrorProvider(episodeId).notifier).clear();
        ref
            .read(sceneBeatOverlaysProvider(episodeId).notifier)
            .add(
              SceneBeatOverlay(
                id: scene.id,
                version: version,
                beats: [
                  for (final beat in _currentBeats(scene))
                    if (beat.characterId != characterId) beat,
                ],
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
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
    // Refetch boundary (issue #366 review): recompute the TTL result so a
    // later loading state never consumes a pre-write memo.
    ref.invalidate(scenesCacheStaleProvider(episodeId));
    final res = await ref.read(scenesListFetchProvider(episodeId).future);
    return res.match((_) => null, (rows) => rows);
  }
}

/// Localized client-side copy for scene costume-beat command failures,
/// keyed on the stable problem `code` (never the server's localized
/// `detail`) — issue #546.
String sceneBeatErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'scene.character-not-in-scene' => l10n.sceneBeatErrorNotInScene,
      'scene.beat-not-found' => l10n.sceneBeatErrorNotFound,
      'scene.validation' => l10n.sceneBeatErrorValidation,
      // 409 `concurrency.version-mismatch`: the backend's sole
      // version-conflict code (same copy as every other controller).
      'concurrency.version-mismatch' => l10n.costumeCategoryErrorChanged,
      // Capability denial: the user is SIGNED IN but lacks the
      // `assign_costumes` capability — the forbidden narrative, never the
      // sign-in copy.
      'costume.forbidden' => l10n.costumeErrorForbidden,
      // Membership could not be resolved (pending / fetch failure).
      'membership.pending' => l10n.costumeErrorMembership,
      'authz.denied' || 'auth.session_required' => l10n.blocksCreateErrorSignIn,
      _ when error.code.startsWith('transport.') => l10n.sceneBeatErrorNetwork,
      _ => l10n.sceneBeatErrorGeneric(error.code),
    };
