// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
import '../../core/uuid.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/piece_domains_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/piece_repository.dart';
import '../../data/photo_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../photos/widgets/photo_gallery.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'pieces_state.dart';

part 'pieces_controller.g.dart';

/// Piece repository: owns network + Drift cache writes.
@riverpod
PieceRepository pieceRepository(Ref ref) => PieceRepository(
  ref.watch(apiClientProvider),
  PieceCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// Photo repository (upload / bytes / delete / watch).
@riverpod
PhotoRepository piecePhotoRepository(Ref ref) =>
    PhotoRepository(ref.watch(apiClientProvider));

/// The injected season-scoped list-fetch seam
/// (`GET /v1/pieces?season_id=…`). Tests override this provider with a
/// fake.
@riverpod
Future<Result<List<PieceView>>> piecesListFetch(
  Ref ref,
  String seasonId,
) async {
  final repo = ref.watch(pieceRepositoryProvider);
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

/// Retained last-good snapshot per season.
@Riverpod(keepAlive: true)
class PiecesPrevRows extends _$PiecesPrevRows {
  @override
  List<PieceView> build(String seasonId) => const [];

  void set(List<PieceView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class PiecesView {
  const PiecesView({required this.rows, required this.isStale, this.error});

  final List<PieceView> rows;
  final bool isStale;
  final ProblemError? error;
}

/// Read-projection controller (seeder watches repository + fetch only).
@Riverpod(keepAlive: false)
class PiecesViewController extends _$PiecesViewController {
  @override
  AsyncValue<PiecesView> build(String seasonId) {
    final repo = ref.watch(pieceRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(seasonId))
          .getOrElse((_) => const <PieceView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(piecesPrevRowsProvider(seasonId)).isEmpty) {
        ref.read(piecesPrevRowsProvider(seasonId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(piecesListFetchProvider(seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<PiecesView>.error(err, StackTrace.current),
        (rows) {
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref.read(piecesPrevRowsProvider(seasonId).notifier).set(rows);
            }),
          );
          return AsyncValue<PiecesView>.data(
            PiecesView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<PiecesView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<PiecesView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one season's pieces (issue #366).
@riverpod
Future<bool> piecesCacheStale(Ref ref, String seasonId) async {
  final repo = ref.watch(pieceRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(seasonId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
PiecesView piecesView(Ref ref, String seasonId) {
  final async = ref.watch(piecesViewControllerProvider(seasonId));
  final prev = ref.watch(piecesPrevRowsProvider(seasonId));
  final ttlStale = ref.watch(piecesCacheStaleProvider(seasonId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => PiecesView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => PiecesView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).
@Riverpod(keepAlive: true)
class PiecesOverlays extends _$PiecesOverlays {
  @override
  List<PieceRowOverlay> build(String seasonId) => const [];

  void add(PieceRowOverlay overlay) =>
      state = [...state.where((o) => o.id != overlay.id), overlay];

  void markAllReconciling() => state = [
    for (final o in state) o.copyWithStatus(status: OverlayStatus.reconciling),
  ];

  /// Drops overlays whose version fence the fresh [projection] passes.
  void pruneWithProjection(List<PieceView> projection) {
    final byId = {for (final c in projection) c.id: c};
    state = state.where((o) {
      final row = byId[o.id];
      // Create-path overlays (id absent) clear once the id projects.
      if (row == null) return true;
      return !shouldClearPieceOverlay(
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

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class PiecesCommandError extends _$PiecesCommandError {
  @override
  PieceCommandFailure? build(String seasonId) => null;

  void set(PieceCommandFailure failure) => state = failure;

  void clear() => state = null;
}

/// Localized client-side copy for piece command failures, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String pieceErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      // 409 `concurrency.version-mismatch`: the echoed aggregate version
      // lost the optimistic-concurrency guard (the backend's ONE
      // version-conflict code — the old
      // `piece.version_conflict`/`concurrency.conflict` keys were never
      // emitted, issue #481). Distinct pull-to-refresh narrative (issue
      // #473 req. #3) so the user resyncs instead of retrying a doomed
      // write.
      'concurrency.version-mismatch' => l10n.pieceErrorChanged,
      'piece.forbidden' || 'authz.denied' => l10n.pieceErrorForbidden,
      'membership.pending' => l10n.pieceErrorMembership,
      'auth.session_required' => l10n.blocksCreateErrorSignIn,
      // Issue #543: the category picked from a foreign season vocabulary
      // (or a category no longer in the piece's permitted set) is
      // rejected at the API edge before any event is written — a distinct
      // narrative so the user re-picks from this season's categories.
      'costume-category.season-mismatch' => l10n.pieceErrorCategorySeason,
      'costume-category.archived' => l10n.pieceErrorCategoryArchived,
      // Issue #544: the detail edit/delete routes answer a dedicated 404
      // (not `piece.validation` 422) so a stale row can be told apart from
      // a real validation failure. The narrative tells the user the row is
      // gone and that the list was refreshed — the bounded reconcile swaps
      // the projection in behind it.
      'piece-detail.not-found' => l10n.pieceErrorDetailNotFound,
      // Issue #534: repertoire add/remove pre-checks. An archived season
      // (#533 terminal state) accepts no further repertoire mutations —
      // distinct narrative so the user understands the season, not the
      // piece, is locked. A vanished target season answers 404.
      'season.archived' => l10n.pieceErrorSeasonArchived,
      'season.not-found' => l10n.pieceErrorSeasonNotFound,
      // The repertoire AUTHZ-GATE answers with the server's generic
      // season-scoped 403 (the same shape the archive route uses).
      'domain.forbidden' => l10n.pieceErrorForbidden,
      _ when error.code.startsWith('transport.') =>
        l10n.costumeCategoryErrorNetwork,
      _ => l10n.pieceErrorGeneric(error.code),
    };

/// Copy for the shared season-scoped command-error banner (list + detail
/// screens), routed by the command ORIGIN.
///
/// Photo commands (upload/delete) share this provider with piece writes;
/// their failures render through [photoErrorCopy] while piece writes use
/// [pieceErrorCopy]. Routing by origin — never by the `photo.*` code
/// prefix (CodeRabbit #4101353471): a photo command can fail with the
/// generic `domain.validation` (a concurrent unassign races the local gate,
/// issue #513) and must still render the photo copy, not the "piece could
/// not be saved" fallback.
String pieceCommandErrorCopy(
  AppLocalizations l10n,
  PieceCommandFailure failure,
) => failure.surface == PieceCommandSurface.photo
    ? photoErrorCopy(l10n, failure.error)
    : pieceErrorCopy(l10n, failure.error);

/// `PiecesController(seasonId)` on the shared reconciliation runner.
@Riverpod(keepAlive: true)
class PiecesController extends _$PiecesController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((c) => c.id).toList();
        },
        hasOverlays: () =>
            ref.read(piecesOverlaysProvider(seasonId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  PiecesScreenState build(String seasonId) {
    final async = ref.watch(piecesViewControllerProvider(seasonId));
    final view = ref.watch(piecesViewProvider(seasonId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<PieceView>>.data(value.rows),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<PieceView>>.error(error, stackTrace),
      _ => const AsyncValue<List<PieceView>>.loading(),
    };
    return PiecesScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(piecesOverlaysProvider(seasonId)),
      commandError: ref.watch(piecesCommandErrorProvider(seasonId)),
    );
  }

  /// Client-side AUTHZ-GATE for piece commands (assign/unassign):
  /// the `assign_costumes` capability is checked BEFORE any network call.
  /// A denial short-circuits with the localized 403 narrative and never
  /// issues the request (provable by a fake repo call count of zero).
  Future<GateDecision> _assignGate() async {
    final session = await _resolveSession();
    if (session == null) return const GateDeny('auth.session_required');
    GateDecision gate;
    try {
      final res = await ref.read(membershipFetchProvider(seasonId).future);
      gate = res.match(
        (_) => const GateDeny('membership.pending'),
        (dto) => checkAssignCapability(dto),
      );
    } on Object {
      gate = const GateDeny('membership.pending');
    }
    return gate;
  }

  /// Client-side AUTHZ-GATE for photo commands (upload/delete): the
  /// **series-scoped** photo policy mirror (issue #535, ADR-035 B2/S2) —
  /// the backend-computed `has_active_costume_role_in_series` predicate,
  /// resolved from the COSTUME (character-first ∪ repertoire — issue #535
  /// review), not from the currently open season: a carried-over piece
  /// opened through a foreign repertoire season gates on its own series.
  /// A client-side denial short-circuits with the localized 403 narrative
  /// and never issues the request.
  ///
  /// A failed membership fetch is `membership.pending` (D3) — and the
  /// provider is invalidated so the NEXT command attempt re-executes the
  /// fetch instead of replaying the cached failure (issue #535 review:
  /// retry-ability).
  Future<GateDecision> _photoGate(PieceView piece) async {
    final session = await _resolveSession();
    if (session == null) return const GateDeny('auth.session_required');
    GateDecision gate;
    try {
      final res = await ref.read(
        seriesMembershipForCostumeProvider(costumeMembershipScope(piece))
            .future,
      );
      gate = res.match((_) {
        // Retry-ability: drop the failed result so a subsequent
        // command re-executes the fetch (the retained Left would
        // otherwise be replayed as a permanent pending).
        ref.invalidate(
          seriesMembershipForCostumeProvider(costumeMembershipScope(piece)),
        );
        return const GateDeny('membership.pending');
      }, checkPiecePhotoCapability);
    } on Object {
      gate = const GateDeny('membership.pending');
    }
    return gate;
  }

  GateDecision? _deny(PieceCommandSurface surface, GateDecision gate) {
    if (gate is GateDeny) {
      _setCommandError(surface, ProblemError(code: gate.code, status: 403));
      return gate;
    }
    return null;
  }

  void _setCommandError(PieceCommandSurface surface, ProblemError error) => ref
      .read(piecesCommandErrorProvider(seasonId).notifier)
      .set(PieceCommandFailure(surface, error));

  /// Resolves the freshest version for [pieceId] at command time (issue
  /// #473). A write must echo the version the server aggregate currently
  /// holds — NEVER the screen-captured snapshot, which can lag behind the
  /// acknowledged state (the editor re-opened cached state, or the reconcile
  /// refetch result never fed back into the view object the editor holds).
  ///
  /// Sources, freshest known state first:
  ///   1. a held overlay's version (this client's latest ack — authoritative
  ///      and above any lagging projection),
  ///   2. the reconciled projection row's version (`piecesViewProvider`),
  ///   3. the screen-passed [fallback] only when nothing fresher is known.
  ///
  /// The backend guard is strict equality (`cmd.version != self.version` →
  /// 422 `domain.validation`), so the value must be the true current
  /// aggregate version. Overlays and projections are both derived from the
  /// same monotone aggregate, so the maximum known version is the correct
  /// estimate — an overlay ack never overtakes the aggregate and a projection
  /// can only lag it.
  int _resolveVersion(String pieceId, int fallback) {
    var version = fallback;
    for (final o in ref.read(piecesOverlaysProvider(seasonId))) {
      if (o.id == pieceId && o.overlay.version > version) {
        version = o.overlay.version;
      }
    }
    for (final row in ref.read(piecesViewProvider(seasonId)).rows) {
      if (row.id == pieceId && row.version > version) {
        version = row.version;
      }
    }
    return version;
  }

  /// Creates a piece shell (empty-body contract D1) and immediately
  /// chains to the first detail (the create sheet handles the chaining;
  /// the overlay row never dead-ends).
  Future<Result<IdVersionResponse>> create({required String name}) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      _setCommandError(PieceCommandSurface.piece, error);
      return const Left(error);
    }
    final repo = ref.read(pieceRepositoryProvider);
    // File the new piece into the current season's repertoire so it is
    // visible in the wardrobe list. The aggregate requires a name (blank is
    // 422 `piece.validation`); the detail screen renames it right after
    // creation.
    final ack = await repo.create(name: name, seasonId: seasonId);
    return ack.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: res.id,
                overlay: PieceView(
                  (b) => b
                    ..id = res.id
                    ..name = name
                    ..notes = ''
                    ..details.replace(const [])
                    ..photos.replace(const [])
                    ..updatedAt = DateTime.now().toUtc()
                    ..version = res.version,
                ),
                acknowledgedVersion: res.version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Adds a detail (pure description — issue #543; the category lives on
  /// the piece). Optimistic-after-2xx on the piece row.
  Future<Result<int>> addDetail({
    required PieceView piece,
    required String text,
    String? subject,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      _setCommandError(PieceCommandSurface.piece, error);
      return const Left(error);
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.addDetail(
      piece.id,
      AddPieceDetailRequest(
        (b) => b
          // Wire id MUST be a real UUIDv7 (contract-typed `uuid`); the
          // optimistic overlay keeps its OWN separate transient placeholder
          // (`pending-detail-<version>`) and is reconciled from the
          // projection response — never from this value (issue #472: the
          // old `'pending'` here 422'd as `domain.validation`).
          ..detail.id = generateUuidV7()
          ..detail.text = text
          ..detail.subject = subject
          ..version = _resolveVersion(piece.id, piece.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        // Unique placeholder id per command (detail cards key on it);
        // the overlay version advances to the ack (see assign).
        final detail = optimisticDetailPlaceholder(
          pendingId: 'pending-detail-$version',
          subject: subject,
          text: text,
        );
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyAddDetailOptimistic(
                  piece,
                  detail,
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

  /// Edits an existing detail (issue #544, PATCH).
  ///
  /// Sends the FULL detail (subject + text), never a patch: a cleared
  /// `subject` must reach the server as an explicit `null` rather than as an
  /// omitted field, or the previous value would silently survive. The wire
  /// `detail.id` is the EXISTING id (the server rejects a body id that
  /// disagrees with the path parameter) — unlike [addDetail], no placeholder
  /// is involved, so issue #472's `'pending'` trap has no path here.
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call — the backend handlers gate on the same predicate
  /// (`authorize_costume_scoped`, ANY season scope of the piece).
  Future<Result<int>> updateDetail({
    required PieceView piece,
    required String detailId,
    required String text,
    String? subject,
  }) async {
    final gate = await _assignGate();
    if (_deny(PieceCommandSurface.piece, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.updateDetail(
      piece.id,
      detailId,
      UpdatePieceDetailRequest(
        (b) => b
          ..detail.id = detailId
          ..detail.subject = subject
          ..detail.text = text
          ..version = _resolveVersion(piece.id, piece.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        _reconcileStaleDetail(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        // Optimistic-after-2xx: the entry is swapped in place on the row copy
        // and the overlay version advances to the ack (same fence as
        // addDetail/assign).
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyUpdateDetailOptimistic(
                  piece,
                  detailId,
                  subject: subject,
                  text: text,
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

  /// Removes a detail (issue #544, DELETE).
  ///
  /// The row leaves the overlay immediately after the 2xx ack; the
  /// projection confirms it on the next refetch. A 404
  /// `piece-detail.not-found` (the row was already gone server-side)
  /// surfaces in the command-error banner and the bounded reconcile resyncs
  /// the list — no silent discard.
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call — the backend handler gates on the same predicate
  /// (`authorize_costume_scoped`, ANY season scope of the piece).
  Future<Result<int>> removeDetail({
    required PieceView piece,
    required String detailId,
  }) async {
    final gate = await _assignGate();
    if (_deny(PieceCommandSurface.piece, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.removeDetail(
      piece.id,
      detailId,
      VersionRequest(
        (b) => b..version = _resolveVersion(piece.id, piece.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        _reconcileStaleDetail(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyRemoveDetailOptimistic(
                  piece,
                  detailId,
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

  /// Sets (or clears) the piece's single category (issue #543).
  ///
  /// `categoryId == null` clears; setting the category that is already set
  /// (or clearing an un-categorised piece) is an idempotent client-side
  /// no-op — the backend treats the identical value as a state-based no-op
  /// (#515 precedent), so the version never advances and no network call is
  /// needed. The optimistic overlay swaps the category into the freshest
  /// effective row after the 2xx ack; bounded reconcile swaps in the
  /// projected row once it reaches the ack version (same fence as
  /// assign/addDetail).
  ///
  /// Error surfaces: 409 `costume-category.season-mismatch` (foreign-
  /// season vocabulary, blocked at the API edge BEFORE dispatch), 409
  /// `costume-category.archived`, 404 `costume-category.not-found` —
  /// plus the classic version-conflict 409. All render via the command-
  /// error banner keyed on the stable problem `code` (never backend
  /// `detail`) — no silent discard (AGENTS.md §4).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call. The backend handler authorizes the same predicate
  /// (`authorize_costume_scoped` — costume role in ANY season scope of the
  /// piece), so the client mirrors exactly that seam.
  Future<Result<int>> setCategory({
    required PieceView piece,
    required String? categoryId,
    String? categoryName,
  }) {
    // Serialize category commands per piece (CodeRabbit #4126529962):
    // while a selection is pending, a newer one awaits its completion so
    // it no-op-detects and version-echoes against the FRESHEST effective
    // state (the older op's ack overlay), never against a racing snapshot.
    // The chained future is pre-caught: the prior op's error must not
    // reject the newer op's await — it lives in the command-error banner
    // (and was returned to the prior caller).
    final prior = _categoryOps.remove(piece.id);
    final op = _setCategoryEffective(
      prior: prior,
      piece: piece,
      categoryId: categoryId,
      categoryName: categoryName,
    );
    final tracked = op.then<void>(
      (_) {},
      // Pre-caught: the prior op's error must not reject the newer op's
      // await — it lives in the command-error banner (and was returned to
      // the prior caller).
      onError: (_) {},
    );
    _trackCategoryOp(piece.id, tracked);
    return op;
  }

  /// Retains the serialized category op as the next op's per-piece
  /// predecessor. `addEntries` (void) statt einer Map-Zuweisung: eine
  /// Zuweisungs-Anweisung trägt den RHS-Typ (`Future<void>`) und die
  /// discard_result-Regel flaggt korrekt jedes Future-typed Statement —
  /// dieses Retain ist kein Discard, sondern die Serialisierungs-Kette.
  void _trackCategoryOp(String id, Future<void> tracked) {
    _categoryOps.addEntries([MapEntry(id, tracked)]);
  }

  /// In-flight category command per piece id (serialization chain).
  final Map<String, Future<void>> _categoryOps = {};

  /// Serialized body of [setCategory]: swallows the prior op's outcome (its
  /// error also lives in the command-error banner — no silent discard),
  /// then dispatches against the freshest effective row.
  Future<Result<int>> _setCategoryEffective({
    required Future<void>? prior,
    required PieceView piece,
    required String? categoryId,
    String? categoryName,
  }) async {
    if (prior != null) {
      try {
        await prior;
      } on Object {
        // The prior op already surfaced its failure via the command-error
        // provider (or returned it to its own caller); never a throw.
      }
    }
    return _setCategoryFresh(
      piece: piece,
      categoryId: categoryId,
      categoryName: categoryName,
    );
  }

  /// Category dispatch against the freshest effective row (CodeRabbit
  /// #4126529962): held overlay first (this client's latest ack), then the
  /// projection, then the screen-passed snapshot — never an older snapshot
  /// behind a newer ack. The overlay merges the category onto that row, so
  /// an acknowledged notes value (or any other field edit) survives in the
  /// optimistic window.
  Future<Result<int>> _setCategoryFresh({
    required PieceView piece,
    required String? categoryId,
    String? categoryName,
  }) async {
    var effective = piece;
    for (final o in ref.read(piecesOverlaysProvider(seasonId))) {
      if (o.id == piece.id && o.overlay.version >= effective.version) {
        effective = o.overlay;
      }
    }
    for (final row in ref.read(piecesViewProvider(seasonId)).rows) {
      if (row.id == piece.id && row.version > effective.version) {
        effective = row;
      }
    }
    // Idempotent no-op against the FRESHEST state: the requested category
    // already holds. The server-side no-op returns the UNCHANGED version —
    // echoing the effective row's version is exactly that ack.
    // Authorization-neutral: this path dispatches no mutating request
    // (same rationale as [assign]'s same-character shortcut).
    if (effective.categoryId == categoryId) {
      return Right<ProblemError, int>(effective.version);
    }
    // AUTHZ-GATE: capability check before any network call.
    final gate = await _assignGate();
    if (_deny(PieceCommandSurface.piece, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.setCategory(
      piece.id,
      SetPieceCategoryRequest(
        (b) => b
          ..categoryId = categoryId
          ..version = _resolveVersion(piece.id, effective.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyCategoryOptimistic(
                  effective,
                  categoryId,
                  categoryName,
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

  /// Adds the piece to a season's repertoire (issue #534).
  ///
  /// Idempotent against the freshest effective row (issue #515 lesson): a
  /// season already in the repertoire no-ops client-side with the UNCHANGED
  /// version — echoing it is exactly the server's ack, so no network call
  /// is needed.
  ///
  /// Error surfaces: 409 `season.archived` (target season archived, blocked
  /// at the API edge BEFORE dispatch), 404 `season.not-found`, 403
  /// `domain.forbidden` (the server gates the TARGET season's costume role;
  /// this client's session scope is the current season, so a cross-season
  /// denial surfaces through the command-error banner) plus the classic
  /// version-conflict 409 — all code-keyed, no silent discard.
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before any network
  /// call. The backend handler additionally authorizes the TARGET season's
  /// membership; the mirror here is the session/capability check this
  /// client can resolve locally (the AGENTS.md S5 rule: never deny on the
  /// season union client-side — the server owns the target-season check).
  Future<Result<int>> addToSeason({
    required PieceView piece,
    required String seasonId,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      _setCommandError(PieceCommandSurface.piece, error);
      return const Left(error);
    }
    final effective = _freshestPiece(piece);
    // Idempotent no-op against the FRESHEST state (Authorization-neutral:
    // dispatches no mutating request, same rationale as [setCategory]).
    if (effective.seasonIds.contains(seasonId)) {
      return Right<ProblemError, int>(effective.version);
    }
    // AUTHZ-GATE: capability check before any network call.
    final gate = await _assignGate();
    if (_deny(PieceCommandSurface.piece, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.addToSeason(
      effective.id,
      AddPieceToSeasonRequest(
        (b) => b
          ..seasonId = seasonId
          ..version = _resolveVersion(piece.id, effective.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(this.seasonId).notifier).clear();
        ref
            .read(piecesOverlaysProvider(this.seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyAddSeasonOptimistic(
                  effective,
                  seasonId,
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

  /// Removes the piece from a season's repertoire (issue #534). Idempotent
  /// mirror of [addToSeason]: an absent season no-ops client-side with the
  /// unchanged version. An empty repertoire is legitimate.
  ///
  /// // AUTHZ-GATE: same seam as [addToSeason].
  Future<Result<int>> removeFromSeason({
    required PieceView piece,
    required String seasonId,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      _setCommandError(PieceCommandSurface.piece, error);
      return const Left(error);
    }
    final effective = _freshestPiece(piece);
    if (!effective.seasonIds.contains(seasonId)) {
      return Right<ProblemError, int>(effective.version);
    }
    // AUTHZ-GATE: capability check before any network call.
    final gate = await _assignGate();
    if (_deny(PieceCommandSurface.piece, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.removeFromSeason(
      effective.id,
      seasonId,
      VersionRequest(
        (b) => b..version = _resolveVersion(piece.id, effective.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(this.seasonId).notifier).clear();
        ref
            .read(piecesOverlaysProvider(this.seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyRemoveSeasonOptimistic(
                  effective,
                  seasonId,
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

  /// The freshest state of one piece across the fence-held overlays and
  /// the projection (repository pattern of `_setCategoryFresh`, without the
  /// serialization chain): a command echo bumps the version, so the next
  /// repertoire op in the same window must fence against it.
  PieceView _freshestPiece(PieceView piece) {
    var effective = piece;
    for (final o in ref.read(piecesOverlaysProvider(seasonId))) {
      if (o.id == piece.id && o.overlay.version >= effective.version) {
        effective = o.overlay;
      }
    }
    for (final row in ref.read(piecesViewProvider(seasonId)).rows) {
      if (row.id == piece.id && row.version > effective.version) {
        effective = row;
      }
    }
    return effective;
  }

  /// Edits notes (PATCH, version echo). Optimistic-after-2xx on the row.
  Future<Result<int>> updateNotes({
    required PieceView piece,
    required String notes,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      _setCommandError(PieceCommandSurface.piece, error);
      return const Left(error);
    }
    final repo = ref.read(pieceRepositoryProvider);
    final res = await repo.updateNotes(
      piece.id,
      UpdatePieceNotesRequest(
        (b) => b
          ..notes = notes
          ..version = _resolveVersion(piece.id, piece.version),
      ),
    );
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.piece, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .add(
              PieceRowOverlay(
                id: piece.id,
                overlay: applyNotesOptimistic(
                  piece,
                  notes,
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

  /// Uploads prepared photo bytes (raw bytes, content-type header).
  /// Returns the Gallery ack; the screen reconciles via the piece refetch
  /// + [PhotoRepository.watch].
  ///
  /// // AUTHZ-GATE: **series-scoped** photo policy checked before the call
  /// (issue #535, ADR-035 B2/S2 — the mirror reads the backend-computed
  /// `has_active_costume_role_in_series` for the piece's OWN series,
  /// resolved character-first ∪ repertoire — issue #535 review). The
  /// server re-resolves and re-checks authoritatively. The server's
  /// `piece.container-unresolved` for a piece with no resolvable
  /// container renders through [photoErrorCopy].
  Future<Result<PhotoView>> uploadPhoto({
    required PieceView piece,
    required Uint8ListBytes bytes,
    required String contentType,
  }) async {
    // AUTHZ-GATE: photo capability checked before any network call.
    final gate = await _photoGate(piece);
    if (_deny(PieceCommandSurface.photo, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(piecePhotoRepositoryProvider);
    final res = await repo.upload(piece.id, bytes.bytes, contentType);
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.photo, err);
        return Left<ProblemError, PhotoView>(err);
      },
      (view) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, PhotoView>(view);
      },
    );
  }

  /// Deletes a piece photo (confirm-first in the UI; 204 → optimistic
  /// removal + reconcile).
  ///
  /// // AUTHZ-GATE: **series-scoped** photo policy checked before the call
  /// (issue #535); the piece's owning series is resolved character-first
  /// ∪ repertoire (issue #535 review) for the same reason as [uploadPhoto].
  Future<Result<void>> deletePhoto({
    required PieceView piece,
    required String photoId,
  }) async {
    // AUTHZ-GATE: photo capability checked before any network call.
    final gate = await _photoGate(piece);
    if (_deny(PieceCommandSurface.photo, gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(piecePhotoRepositoryProvider);
    final res = await repo.delete(piece.id, photoId);
    return res.match(
      (err) {
        _setCommandError(PieceCommandSurface.photo, err);
        return Left<ProblemError, void>(err);
      },
      (_) {
        ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
        unawaited(refresh());
        return const Right<ProblemError, void>(null);
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

  /// Resyncs the list after a detail command failed with
  /// `piece-detail.not-found` (issue #544).
  ///
  /// That 404 means the server no longer holds the addressed detail, so the
  /// row on screen is stale whatever the client intended. The
  /// `pieceErrorDetailNotFound` copy tells the user "the list was
  /// refreshed" — so this has to actually happen, or the banner promises
  /// something the client never does and a second tap on the same row
  /// returns the identical 404 (CodeRabbit review on PR #561).
  ///
  /// Every OTHER error is left alone: a 409 version conflict or a transport
  /// failure says nothing about the detail's existence, and refetching on
  /// those would fight the user's retry.
  void _reconcileStaleDetail(ProblemError err) {
    if (err.code != 'piece-detail.not-found') return;
    unawaited(reconcile());
  }

  Future<void> refresh() async {
    ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();
    await reconcile();
  }

  /// Fetches the single piece DETAIL and upserts it into the Drift cache.
  ///
  /// The list route (`GET /v1/pieces?season_id=…`) returns piece rows
  /// WITHOUT their child collections — the server's list query maps the raw
  /// projection row (`map_costume_row`) and therefore leaves `details` and
  /// `photos` empty. Only `GET /v1/pieces/{id}` runs the enrichment. The
  /// detail screen renders from the cached LIST rows, so photos (and piece
  /// details) were structurally unreachable from the editor: every gallery
  /// showed the empty placeholder, no matter how often the user refreshed,
  /// pulled to refresh, cleared the cache or force-stopped the app — the
  /// refetched list simply carried no photos again.
  ///
  /// Writing the enriched detail over the cached list row repairs both
  /// surfaces at once: the cache row now carries the photos, and every
  /// reader of `cachedRows` (detail editor, gallery) sees them.
  Future<Result<PieceView>> loadDetail(String pieceId) =>
      ref.read(pieceRepositoryProvider).getAndCache(seasonId, pieceId);

  void dismissCommandError() =>
      ref.read(piecesCommandErrorProvider(seasonId).notifier).clear();

  Future<List<PieceView>?> _refetchProjection() async {
    ref.invalidate(piecesListFetchProvider(seasonId));
    ref.invalidate(piecesCacheStaleProvider(seasonId));
    final res = await ref.read(piecesListFetchProvider(seasonId).future);
    return res.match((_) => null, (rows) {
      // The version fence owns overlay clearing: prune against the fresh
      // projection here so a stale row never restores pre-command state.
      if (ref.mounted) {
        ref
            .read(piecesOverlaysProvider(seasonId).notifier)
            .pruneWithProjection(rows);
      }
      return rows;
    });
  }
}

/// Typed wrapper so the upload seam stays explicit at call sites.
class Uint8ListBytes {
  const Uint8ListBytes(this.bytes);

  final Uint8List bytes;
}
