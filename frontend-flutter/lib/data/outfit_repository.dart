// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/piece_domains_cache_dao.dart';

/// Read/write repository for a character's **outfits** (the composed looks a
/// character wears).
///
/// An outfit aggregates `0..n` fundus pieces and is what a scene casts
/// (`SceneOutfitBeat`). There is exactly one list route — per character — so
/// the cache slice is character-scoped ([OutfitCacheDao]).
///
/// Same discipline as [PieceRepository]: never throws ([Result] in/out), a
/// successful fetch snapshot-replaces the character slice, a failure leaves
/// the cache untouched, and every mutation returns the acknowledged aggregate
/// version for the optimistic fence.
class OutfitRepository extends BaseRepository {
  const OutfitRepository(super.api, this.cache);

  final OutfitCacheDao cache;

  /// Character-scoped fetch + snapshot-replace
  /// (`GET /v1/characters/{character_id}/outfits`), paginated through every
  /// page so the snapshot is never truncated.
  Future<Result<List<OutfitView>>> listByCharacter(
    String characterId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<OutfitView>> fetched = await fetchAllPages<OutfitView>(
      ({required int limit, required int offset}) =>
          api.getHandlersApi().listCharacterOutfits(characterId: characterId),
      dtoInvalidCode: 'outfit.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<OutfitView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        try {
          await cache.applySnapshotForCharacter(characterId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the character's cached outfits WITH the
  /// TTL staleness verdict.
  Future<Result<({List<OutfitView> rows, bool stale})>> readCachedFresh(
    String characterId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) async {
    try {
      return Right(
        await cache.readByCharacterFresh(characterId, ttl: ttl, clock: clock),
      );
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Single-entity fetch; the projection row is authoritative.
  Future<Result<OutfitView>> get(String id) =>
      run(() => api.getHandlersApi().getOutfit(id: id));

  /// Creates a look for [characterId]. `pieceIds` may be empty (an empty
  /// shell establishes a named look before the garments are catalogued).
  Future<Result<IdVersionResponse>> create({
    required String characterId,
    required String name,
    List<String> pieceIds = const [],
  }) => run(
    () => api.getHandlersApi().createOutfit(
      createOutfitRequest: CreateOutfitRequest(
        (b) => b
          ..characterId = characterId
          ..name = name
          ..pieceIds.addAll(pieceIds),
      ),
    ),
  );

  /// Forks [sourceOutfitId] into an independent copy (copy-on-write variant).
  /// Omitted fields inherit from the source on the server.
  Future<Result<IdVersionResponse>> createVariant(
    String sourceOutfitId, {
    String? name,
    List<String>? pieceIds,
    String? notes,
  }) => run(
    () => api.getHandlersApi().createOutfitVariant(
      id: sourceOutfitId,
      createOutfitVariantRequest: CreateOutfitVariantRequest(
        (b) => b
          ..name = name
          ..pieceIds.addAll(pieceIds ?? const [])
          ..notes = notes,
      ),
    ),
  );

  Future<Result<int>> rename(String id, RenameOutfitRequest request) => run(
    () =>
        api.getHandlersApi().renameOutfit(id: id, renameOutfitRequest: request),
  );

  Future<Result<int>> updateNotes(
    String id,
    UpdateOutfitNotesRequest request,
  ) => run(
    () => api.getHandlersApi().updateOutfitNotes(
      id: id,
      updateOutfitNotesRequest: request,
    ),
  );

  /// Adds a piece to the look (`POST /v1/outfits/{id}/pieces`). Idempotent:
  /// adding a piece the outfit already holds is a no-op success.
  Future<Result<int>> addPiece(String id, AddOutfitPieceRequest request) => run(
    () => api.getHandlersApi().addOutfitPiece(
      id: id,
      addOutfitPieceRequest: request,
    ),
  );

  /// Removes a piece (`DELETE /v1/outfits/{id}/pieces/{piece_id}?version=N`).
  Future<Result<int>> removePiece(String id, String pieceId, int version) =>
      run(
        () => api.getHandlersApi().removeOutfitPiece(
          id: id,
          pieceId: pieceId,
          version: version,
        ),
      );

  /// Empties one character's cached outfits (sign-out / backend switch).
  Future<Result<void>> clearCache(String characterId) async {
    try {
      await cache.clearCharacter(characterId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}

/// Optimistic overlay: a renamed look.
OutfitView applyOutfitRenameOptimistic(OutfitView row, String name) =>
    row.rebuild((b) => b..name = name);

/// Optimistic overlay: notes replaced.
OutfitView applyOutfitNotesOptimistic(OutfitView row, String notes) =>
    row.rebuild((b) => b..notes = notes);

/// Optimistic overlay: appends a piece view when not already present (a
/// duplicate would desync the id-keyed list until the projection catches up).
OutfitView applyOutfitAddPieceOptimistic(
  OutfitView row,
  OutfitPieceView piece,
) {
  // Both id collections guard the duplicate: `pieces` carries the joined
  // rows, `pieceIds` the aggregate's reference list — a look whose joined
  // row has not projected yet would otherwise desync the id-keyed list.
  if (row.pieces.any((p) => p.pieceId == piece.pieceId) ||
      row.pieceIds.contains(piece.pieceId)) {
    return row;
  }
  return row.rebuild((b) => b.pieces.add(piece));
}

/// Optimistic overlay: drops a piece from the look.
OutfitView applyOutfitRemovePieceOptimistic(OutfitView row, String pieceId) {
  final remaining = row.pieces.where((p) => p.pieceId != pieceId);
  return row.rebuild(
    (b) => b.pieces
      ..clear()
      ..addAll(remaining),
  );
}

/// Version-fence clear condition: the overlay is dropped only once the
/// refetched projection row has reached the acknowledged version.
bool shouldClearOutfitOverlay({
  required OutfitView projection,
  required int acknowledgedVersion,
}) => projection.version >= acknowledgedVersion;
