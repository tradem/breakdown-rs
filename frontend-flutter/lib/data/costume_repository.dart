// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/costume_domains_cache_dao.dart';

/// Read/write repository for the `Costume` aggregate boundary (scoped to a
/// Season).
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [CostumeCacheDao] — the same
/// discipline as [CostumeCategoryRepository]: a successful fetch applies the
/// season-scoped snapshot (server order = insertion order), a fetch [Left]
/// returns the error without mutating the cache.
///
/// Create is deliberately empty-bodied (D1): `POST /v1/costumes` carries an
/// empty JSON object; contents are added by follow-up commands.
/// Unassign sends `version` only (backend issue #336 corrected the spec to
/// `VersionRequest`).
class CostumeRepository extends BaseRepository {
  const CostumeRepository(super.api, this.cache);

  final CostumeCacheDao cache;

  /// Season-scoped fetch + snapshot-replace
  /// (`GET /v1/costumes?season_id=…`).
  ///
  /// On [Right] applies the season-scoped snapshot and returns the rows. On
  /// [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch.
  ///
  /// Paginates through every page (issue #385) so the snapshot is never
  /// truncated to a single page.
  Future<Result<List<CostumeView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<CostumeView>> fetched = await fetchAllPages<CostumeView>(
      ({required int limit, required int offset}) => api
          .getHandlersApi()
          .listCostumes(seasonId: seasonId, limit: limit, offset: offset),
      dtoInvalidCode: 'costume.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<CostumeView>>(err),
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

  /// Pure Drift read (no network) of the season's cached costumes.
  Future<Result<List<CostumeView>>> readCached(String seasonId) async {
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

  /// Single-entity fetch + cache: GET costume, upsert on success (scoped to
  /// [seasonId]), no mutation on failure.
  Future<Result<CostumeView>> getAndCache(
    String seasonId,
    String id, {
    Clock clock = Clock.system,
  }) async {
    final fetched = await run(() => api.getHandlersApi().getCostume(id: id));
    return fetched.match((err) async => Left<ProblemError, CostumeView>(err), (
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

  /// Creates a costume shell (empty-body contract D1).
  Future<Result<IdVersionResponse>> create(JsonObject body) =>
      run(() => api.getHandlersApi().createCostume(body: body));

  /// Creates a costume shell with the empty contract body.
  Future<Result<IdVersionResponse>> createEmpty() =>
      create(JsonObject(const <String, Object?>{}));

  Future<Result<CostumeView>> get(String id) =>
      run(() => api.getHandlersApi().getCostume(id: id));

  Future<Result<int>> addDetail(String id, AddCostumeDetailRequest request) =>
      run(
        () => api.getHandlersApi().addCostumeDetail(
          id: id,
          addCostumeDetailRequest: request,
        ),
      );

  Future<Result<int>> updateNotes(
    String id,
    UpdateCostumeNotesRequest request,
  ) => run<int>(
    () => api.getHandlersApi().updateCostumeNotes(
      id: id,
      updateCostumeNotesRequest: request,
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

  Future<Result<int>> assign(String id, AssignCostumeRequest request) => run(
    () => api.getHandlersApi().assignCostume(
      id: id,
      assignCostumeRequest: request,
    ),
  );

  Future<Result<int>> unassign(String id, VersionRequest request) => run(
    () => api.getHandlersApi().unassignCostume(id: id, versionRequest: request),
  );

  /// Empties the season's costume rows (sign-out / backend-switch resets).
  Future<Result<void>> clearCache(String seasonId) async {
    try {
      await cache.clearSeason(seasonId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}

/// Optimistic overlay edit for the costume row's `character_id`
/// (assign path): returns a copy carrying the picked character id.
///
/// Applied ONLY after the 2xx acknowledgement (optimistic-after-2xx).
CostumeView applyAssignOptimistic(CostumeView row, String characterId) =>
    row.rebuild((b) => b..characterId = characterId);

/// Optimistic overlay edit for unassign: returns a copy with no assignment.
CostumeView applyUnassignOptimistic(CostumeView row) =>
    row.rebuild((b) => b..characterId = null);

/// Optimistic overlay edit for notes.
CostumeView applyNotesOptimistic(CostumeView row, String notes) =>
    row.rebuild((b) => b..notes = notes);

/// Optimistic overlay edit for add-detail: appends the new detail view.
CostumeView applyAddDetailOptimistic(
  CostumeView row,
  CostumeDetailView detail,
) => row.rebuild((b) => b..details.add(detail));

/// Version-fence clear condition (spec flutter-costumes-screen):
/// the overlay is dropped ONLY when the refetched projection row satisfies
/// `version >= acknowledgedVersion`. A stale projection carrying an older
/// `version` MUST keep the overlay visible rather than restore the
/// pre-command `character_id`, notes, or details.
bool shouldClearCostumeOverlay({
  required CostumeView projection,
  required int acknowledgedVersion,
}) => projection.version >= acknowledgedVersion;

/// Merges a list of projected rows with row-level optimistic overlays keyed
/// by costume id. Overlays whose fence passes are dropped; stale projections
/// retain the overlay (the overlay row wins until the fence passes).
List<CostumeView> mergeCostumeOverlays({
  required List<CostumeView> projected,
  required Map<String, ({CostumeView overlay, int acknowledgedVersion})>
  overlays,
}) {
  if (overlays.isEmpty) return projected;
  final byId = {for (final r in projected) r.id: r};
  final merged = <CostumeView>[];
  for (final row in projected) {
    final pending = overlays[row.id];
    if (pending == null) {
      merged.add(row);
    } else if (shouldClearCostumeOverlay(
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
/// `costume-detail-<id>`, and repeated additions with a constant id would
/// render duplicate keys. The server id arrives via reconciliation and
/// replaces the placeholder.
CostumeDetailView optimisticDetailPlaceholder({
  required String pendingId,
  required String? subject,
  required String text,
  String? categoryId,
  String? categoryName,
}) => CostumeDetailView(
  (b) => b
    ..id = pendingId
    ..subject = subject
    ..text = text
    ..categoryId = categoryId
    ..categoryName = categoryName,
);

/// Extracts the projected ids for the shared reconciliation coordinator.
Set<String> costumeProjectedIds(List<CostumeView> rows) =>
    rows.map((r) => r.id).toSet();

/// Ensures details list builders accept the placeholder shape above.
BuiltList<CostumeDetailView> costumeDetailsOf(CostumeView view) => view.details;
