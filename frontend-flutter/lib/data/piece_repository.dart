// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/piece_domains_cache_dao.dart';

/// Read/write repository for the `Piece` aggregate boundary (scoped to a
/// Season).
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [PieceCacheDao] — the same
/// discipline as [CostumeCategoryRepository]: a successful fetch applies the
/// season-scoped snapshot (server order = insertion order), a fetch [Left]
/// returns the error without mutating the cache.
///
/// Create is deliberately empty-bodied (D1): `POST /v1/pieces` carries an
/// empty JSON object; contents are added by follow-up commands.
class PieceRepository extends BaseRepository {
  const PieceRepository(super.api, this.cache);

  final PieceCacheDao cache;

  /// Season-scoped fetch + snapshot-replace
  /// (`GET /v1/pieces?season_id=…`).
  ///
  /// On [Right] applies the season-scoped snapshot and returns the rows. On
  /// [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch.
  ///
  /// Paginates through every page (issue #385) so the snapshot is never
  /// truncated to a single page.
  Future<Result<List<PieceView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<PieceView>> fetched = await fetchAllPages<PieceView>(
      ({required int limit, required int offset}) => api
          .getHandlersApi()
          .listPieces(seasonId: seasonId, limit: limit, offset: offset),
      dtoInvalidCode: 'piece.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<PieceView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        try {
          await cache.applySnapshotForSeason(seasonId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the season's cached pieces.
  Future<Result<List<PieceView>>> readCached(String seasonId) async {
    try {
      return Right(await cache.readBySeason(seasonId));
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns `true` when any cached row of the season is older than [ttl].
  Future<bool> isCacheStale(
    String seasonId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) => cache.isSeasonExpired(seasonId, ttl, clock: clock);

  /// Single-entity fetch + cache: GET piece, upsert on success (scoped to
  /// [seasonId]), no mutation on failure.
  Future<Result<PieceView>> getAndCache(
    String seasonId,
    String id, {
    Clock clock = Clock.system,
  }) async {
    final fetched = await run(() => api.getHandlersApi().getPiece(id: id));
    return fetched.match((err) async => Left<ProblemError, PieceView>(err), (
      view,
    ) async {
      try {
        await cache.upsert(seasonId, view, clock.now());
      } on Object {
        return const Left(ProblemError(code: 'cache.write_failed'));
      }
      return Right(view);
    });
  }

  /// Catalogues a fundus piece.
  ///
  /// `name` is required by the aggregate (422 `piece.validation` on a blank
  /// name); `seasonId` files it into that season's repertoire and
  /// `categoryId` sets its single category up front (the API edge pre-checks
  /// the category's season membership).
  Future<Result<IdVersionResponse>> create({
    required String name,
    String? seasonId,
    String? categoryId,
  }) => run(
    () => api.getHandlersApi().createPiece(
      createPieceRequest: CreatePieceRequest(
        (b) => b
          ..name = name
          ..seasonId = seasonId
          ..categoryId = categoryId,
      ),
    ),
  );

  /// Renames the piece (`PATCH /v1/pieces/{id}/name`). Names are not unique.
  Future<Result<int>> rename(String id, RenamePieceRequest request) => run(
    () => api.getHandlersApi().renamePiece(id: id, renamePieceRequest: request),
  );

  Future<Result<PieceView>> get(String id) =>
      run(() => api.getHandlersApi().getPiece(id: id));

  Future<Result<int>> addDetail(String id, AddPieceDetailRequest request) =>
      run(
        () => api.getHandlersApi().addPieceDetail(
          id: id,
          addPieceDetailRequest: request,
        ),
      );

  Future<Result<int>> updateNotes(String id, UpdatePieceNotesRequest request) =>
      run<int>(
        () => api.getHandlersApi().updatePieceNotes(
          id: id,
          updatePieceNotesRequest: request,
        ),
      );

  Future<Result<int>> updateMeasurements(
    String id,
    UpdateMeasurementsRequest request,
  ) => run(
    () => api.getHandlersApi().updateMeasurements(
      id: id,
      updateMeasurementsRequest: request,
    ),
  );

  /// Adds the piece to a season's repertoire (issue #534,
  /// `POST /v1/pieces/{id}/seasons`). Idempotent on the server: a season
  /// already in the repertoire is a no-op success with the unchanged
  /// version. The response is the command acknowledgement (the new — or
  /// unchanged — `AggregateVersion`); the projected row update is eventual
  /// (optimistic overlay + bounded reconcile).
  Future<Result<int>> addToSeason(String id, AddPieceToSeasonRequest request) =>
      run(
        () => api.getHandlersApi().addPieceToSeason(
          id: id,
          addPieceToSeasonRequest: request,
        ),
      );

  /// Removes the piece from a season's repertoire (issue #534,
  /// `DELETE /v1/pieces/{id}/seasons/{season_id}`). Idempotent mirror of
  /// [addToSeason]: an absent season is a no-op success with the unchanged
  /// version.
  Future<Result<int>> removeFromSeason(
    String id,
    String seasonId,
    VersionRequest request,
  ) => run(
    () => api.getHandlersApi().removePieceFromSeason(
      id: id,
      seasonId: seasonId,
      versionRequest: request,
    ),
  );

  /// Sets (or clears) the piece's single category (issue #543,
  /// `POST /v1/pieces/{id}/category`). The backend response is the
  /// command acknowledgement (the new `AggregateVersion`); the projected
  /// row update is eventual (optimistic overlay + bounded reconcile).
  /// `request.categoryId == null` clears the piece's category.
  Future<Result<int>> setCategory(String id, SetPieceCategoryRequest request) =>
      run(
        () => api.getHandlersApi().setPieceCategory(
          id: id,
          setPieceCategoryRequest: request,
        ),
      );

  /// Edits an existing detail (issue #544,
  /// `PATCH /v1/pieces/{id}/details/{detail_id}`). The request carries the
  /// FULL detail, not a patch — the backend rejects a body id that disagrees
  /// with [detailId] (422) and answers 404 `piece-detail.not-found` for an
  /// unknown detail. The response is the command acknowledgement (the new
  /// `AggregateVersion`); the projected row update is eventual (optimistic
  /// overlay + bounded reconcile).
  Future<Result<int>> updateDetail(
    String id,
    String detailId,
    UpdatePieceDetailRequest request,
  ) => run(
    () => api.getHandlersApi().updatePieceDetail(
      id: id,
      detailId: detailId,
      updatePieceDetailRequest: request,
    ),
  );

  /// Removes a detail (issue #544,
  /// `DELETE /v1/pieces/{id}/details/{detail_id}`, body = the piece
  /// aggregate's `VersionRequest` echo). Returns the new aggregate version.
  Future<Result<int>> removeDetail(
    String id,
    String detailId,
    VersionRequest request,
  ) => run(
    () => api.getHandlersApi().removePieceDetail(
      id: id,
      detailId: detailId,
      versionRequest: request,
    ),
  );

  /// Empties the season's piece rows (sign-out / backend-switch resets).
  Future<Result<void>> clearCache(String seasonId) async {
    try {
      await cache.clearSeason(seasonId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}

/// Optimistic overlay edit for notes.
PieceView applyNotesOptimistic(PieceView row, String notes) =>
    row.rebuild((b) => b..notes = notes);

/// Optimistic overlay edit for add-detail: appends the new detail view.
PieceView applyAddDetailOptimistic(PieceView row, PieceDetailView detail) =>
    row.rebuild((b) => b..details.add(detail));

/// Optimistic overlay edit for a detail edit (issue #544): replaces the
/// entry with the matching [detailId] in place.
///
/// The entry keeps its POSITION — the aggregate updates the existing
/// `PieceDetail` in its `details` vec and the projector overwrites the row
/// on `(piece_id, detail_id)`, so re-appending would flicker the card down
/// the list. An unknown [detailId] is left untouched rather than appended:
/// the server would have answered 404, so the row cannot be missing from a
/// state this command was allowed to run against.
PieceView applyUpdateDetailOptimistic(
  PieceView row,
  String detailId, {
  String? subject,
  required String text,
}) {
  // The detail list is read off the VALUE, not off the builder: inside a
  // built_value builder `b.details` is the `ListBuilder` accessor, not a
  // getter for the current list.
  final updated = row.details
      .map(
        (d) => d.id == detailId
            ? d.rebuild(
                (db) => db
                  ..subject = subject
                  ..text = text,
              )
            : d,
      )
      .toList();
  return row.rebuild(
    (b) => b.details
      ..clear()
      ..addAll(updated),
  );
}

/// Optimistic overlay edit for a detail delete (issue #544): the row leaves
/// the overlay immediately after the 2xx ack and the projection confirms it
/// on the next refetch.
PieceView applyRemoveDetailOptimistic(PieceView row, String detailId) {
  final remaining = row.details.where((d) => d.id != detailId);
  return row.rebuild(
    (b) => b.details
      ..clear()
      ..addAll(remaining),
  );
}

/// Optimistic overlay edit for the piece-level category (issue #543):
/// the wire acknowledgement already froze the aggregate version; the
/// category id + denormalised name are swapped in on the row copy.
///
/// The name is denormalised at the UI boundary — the projector resolves
/// `category_name` best-effort at read time, and the picker always holds
/// the acted-on list row, so the overlay never invents state: it carries
/// exactly the (id, name) pair the visible option had.
PieceView applyCategoryOptimistic(
  PieceView row,
  String? categoryId,
  String? categoryName,
) => row.rebuild(
  (b) => b
    ..categoryId = categoryId
    ..categoryName = categoryName,
);

/// Optimistic overlay edit for repertoire add (issue #534): appends the
/// season when not yet present (a duplicate entry would desync the id-based
/// keys until the projection swaps in behind the fence).
PieceView applyAddSeasonOptimistic(PieceView row, String seasonId) =>
    row.seasonIds.contains(seasonId)
    ? row
    : row.rebuild((b) => b..seasonIds.add(seasonId));

/// Optimistic overlay edit for repertoire remove (issue #534): drops the
/// season when present.
PieceView applyRemoveSeasonOptimistic(PieceView row, String seasonId) =>
    row.rebuild((b) => b..seasonIds.remove(seasonId));

/// Version-fence clear condition (spec flutter-pieces-screen):
/// the overlay is dropped ONLY when the refetched projection row satisfies
/// `version >= acknowledgedVersion`. A stale projection carrying an older
/// `version` MUST keep the overlay visible rather than restore the
/// pre-command `character_id`, notes, or details.
bool shouldClearPieceOverlay({
  required PieceView projection,
  required int acknowledgedVersion,
}) => projection.version >= acknowledgedVersion;

/// Merges a list of projected rows with row-level optimistic overlays keyed
/// by piece id. Overlays whose fence passes are dropped; stale projections
/// retain the overlay (the overlay row wins until the fence passes).
List<PieceView> mergePieceOverlays({
  required List<PieceView> projected,
  required Map<String, ({PieceView overlay, int acknowledgedVersion})> overlays,
}) {
  if (overlays.isEmpty) return projected;
  final byId = {for (final r in projected) r.id: r};
  final merged = <PieceView>[];
  for (final row in projected) {
    final pending = overlays[row.id];
    if (pending == null) {
      merged.add(row);
    } else if (shouldClearPieceOverlay(
      projection: row,
      acknowledgedVersion: pending.acknowledgedVersion,
    )) {
      merged.add(row);
    } else {
      merged.add(pending.overlay);
    }
  }
  // Overlays for ids absent from the projection (create path) are appended.
  for (final entry in overlays.entries) {
    if (!byId.containsKey(entry.key)) merged.add(entry.value.overlay);
  }
  return merged;
}

/// Builds an empty optimistic detail view for the add-detail overlay.
///
/// [pendingId] MUST be unique per command (e.g. derived from the
/// acknowledged aggregate version): detail cards key on
/// `piece-detail-<id>`, and repeated additions with a constant id would
/// render duplicate keys. The server id arrives via reconciliation and
/// replaces the placeholder.
PieceDetailView optimisticDetailPlaceholder({
  required String pendingId,
  required String? subject,
  required String text,
}) => PieceDetailView(
  (b) => b
    ..id = pendingId
    ..subject = subject
    ..text = text,
);

/// Extracts the projected ids for the shared reconciliation coordinator.
Set<String> pieceProjectedIds(List<PieceView> rows) =>
    rows.map((r) => r.id).toSet();

/// Ensures details list builders accept the placeholder shape above.
BuiltList<PieceDetailView> costumeDetailsOf(PieceView view) => view.details;

/// Version-fence clear condition (spec flutter-costumes-screen): the overlay is
/// dropped ONLY when the refetched projection row satisfies
/// `version >= acknowledgedVersion`. A stale projection carrying an older
/// `version` MUST keep the overlay visible rather than restore the pre-command
/// row.
bool shouldClearCostumeOverlay({
  required PieceView projection,
  required int acknowledgedVersion,
}) => projection.version >= acknowledgedVersion;
