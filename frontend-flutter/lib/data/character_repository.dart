// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/costume_domains_cache_dao.dart';

/// Read/write repository for the `Character` aggregate boundary (scoped to a
/// Season).
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [CharacterCacheDao] — the same
/// discipline as [CostumeCategoryRepository]: a successful fetch applies the
/// season-scoped snapshot, a fetch [Left] returns the error without mutating
/// the cache.
///
/// PATCH commands (`contact`, `measurements`) are full replacements
/// server-side ("God-Command" semantics): the form is pre-filled from the
/// read DTO and `version` echoes it; 409 surfaces "changed elsewhere —
/// refresh" copy keyed on `code` (no auto-bump retry).
class CharacterRepository extends BaseRepository {
  const CharacterRepository(super.api, this.cache);

  final CharacterCacheDao cache;

  /// Season-scoped fetch + snapshot-replace
  /// (`GET /v1/characters?season_id=…`).
  ///
  /// Paginates through every page (issue #385) so the snapshot is never
  /// truncated to a single page.
  Future<Result<List<CharacterView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<CharacterView>> fetched =
        await fetchAllPages<CharacterView>(
          ({required int limit, required int offset}) => api
              .getHandlersApi()
              .listCharacters(seasonId: seasonId, limit: limit, offset: offset),
          dtoInvalidCode: 'character.dto_invalid',
        );
    return fetched.match(
      (err) async => Left<ProblemError, List<CharacterView>>(err),
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

  /// Pure Drift read (no network) of the season's cached characters.
  Future<Result<List<CharacterView>>> readCached(String seasonId) async {
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

  Future<Result<IdVersionResponse>> create(CreateCharacterRequest request) =>
      run(
        () => api.getHandlersApi().createCharacter(
          createCharacterRequest: request,
        ),
      );

  Future<Result<CharacterView>> get(String id) =>
      run(() => api.getHandlersApi().getCharacter(id: id));

  /// Full-replacement contact editor (prefilled from the read DTO).
  Future<Result<int>> updateContact(
    String id,
    UpdateContactInfoRequest request,
  ) => run(
    () => api.getHandlersApi().updateContactInfo(
      id: id,
      updateContactInfoRequest: request,
    ),
  );

  /// Full-replacement measurements editor (all seven fields required
  /// strings; empty strings remain valid submissions — no client-side
  /// numeric validation).
  Future<Result<int>> updateMeasurements(
    String id,
    UpdateMeasurementsRequest request,
  ) => run(
    () => api.getHandlersApi().updateMeasurements(
      id: id,
      updateMeasurementsRequest: request,
    ),
  );

  /// Scene-character binding: assign (picker over the season's characters;
  /// `AssignCharacterRequest.version` is the *scene's* version from the
  /// acted-on `SceneView`).
  Future<Result<int>> assignToScene(
    String sceneId,
    AssignCharacterRequest request,
  ) => run(
    () => api.getHandlersApi().assignSceneCharacter(
      id: sceneId,
      assignCharacterRequest: request,
    ),
  );

  /// Scene-character binding: unassign (DELETE with `?version=` query
  /// parameter, backend issue #341).
  Future<Result<int>> unassignFromScene(
    String sceneId,
    String characterId,
    int sceneVersion,
  ) => run(
    () => api.getHandlersApi().removeSceneCharacter(
      id: sceneId,
      characterId: characterId,
      version: sceneVersion,
    ),
  );

  /// Empties the season's character rows (sign-out / backend-switch resets).
  Future<Result<void>> clearCache(String seasonId) async {
    try {
      await cache.clearSeason(seasonId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}

/// Strict-parses a wire `CharacterCategory` string (unknown variants reject
/// — no guessed meaning). Returns the parsed enum or `null` when unknown.
CharacterCategory? tryParseCharacterCategory(String wire) {
  try {
    return serializers.deserializeWith(CharacterCategory.serializer, wire);
  } on Object {
    return null;
  }
}

/// Builds a full-replacement contact request from form fields + version echo.
UpdateContactInfoRequest buildContactRequest({
  required String? email,
  required String? phone,
  required int version,
}) => UpdateContactInfoRequest(
  (b) => b
    ..contactInfo.email = email
    ..contactInfo.phone = phone
    ..version = version,
);

/// Builds a full-replacement measurements request from form fields + version.
UpdateMeasurementsRequest buildMeasurementsRequest({
  required CharacterMeasurements measurements,
  required int version,
}) => UpdateMeasurementsRequest(
  (b) => b
    ..measurements.replace(measurements)
    ..version = version,
);
