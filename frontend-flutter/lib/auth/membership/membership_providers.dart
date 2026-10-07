// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../src/network/api_client.dart';
import '../auth_providers.dart';
import 'capability.dart';
import 'debug_membership_override.dart';
import 'membership_repository.dart';

part 'membership_providers.g.dart';

/// The permissive membership used in dev-auth mode (Task 5.1): backend
/// ADR-018 D6 parity. Only ever produced when `AppConfig.devAuthMode` is
/// true (dev flavor, no `OIDC_ISS`, `DEV_AUTH_SUB` set) — structurally
/// unreachable in prod.
SeasonMembershipDto devAuthMembership(String seasonId) => SeasonMembershipDto(
  (b) => b
    ..seasonId = seasonId
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(Capability.values.map((c) => c.wireName)),
);

/// The series-level permissive membership for dev-auth mode (issue #535):
/// mirrors [devAuthMembership] one scope up.
SeriesMembershipDto devAuthSeriesMembership(String seriesId) =>
    SeriesMembershipDto(
      (b) => b
        ..seriesId = seriesId
        ..hasActiveCostumeRoleInSeries = true
        ..capabilities.replace(Capability.values.map((c) => c.wireName)),
    );

/// The capability-less denial membership for the Gherkin viewer-role scenario
/// (issue #368): every client-side AUTHZ-GATE resolves to a denial, and the
/// gate fires before any network call (AGENTS.md §5, D6). Test-support only —
/// produced exclusively via [DebugMembershipOverride] in dev-auth mode.
SeasonMembershipDto devAuthDeniedMembership(String seasonId) =>
    SeasonMembershipDto(
      (b) => b
        ..seasonId = seasonId
        ..hasActiveCostumeRoleInSeason = false
        ..capabilities.replace(BuiltList<String>()),
    );

/// The series-level denial membership for the Gherkin viewer-role scenario
/// (issue #535): the series-scoped costume-photo gate resolves to a denial
/// without any network call.
SeriesMembershipDto devAuthDeniedSeriesMembership(String seriesId) =>
    SeriesMembershipDto(
      (b) => b
        ..seriesId = seriesId
        ..hasActiveCostumeRoleInSeries = false
        ..capabilities.replace(BuiltList<String>()),
    );

/// Fetches the season-scoped membership projection (D2 — single endpoint,
/// single source of truth). Returns the `Result` unthrown so the controller
/// below can map it to `AsyncValue` without an async-notifier retry loop.
///
/// Dev-auth mode short-circuits to the permissive membership without any
/// network call (Task 5.1).
@Riverpod(keepAlive: false)
Future<Result<SeasonMembershipDto>> membershipFetch(
  Ref ref,
  String seasonId,
) async {
  final config = ref.watch(appConfigProvider);
  if (config.devAuthMode) {
    // Test-support override (issue #368): the instrumented Gherkin app can
    // flip the dev-auth membership to a capability-less viewer at runtime
    // (driver data channel → DebugMembershipOverride.set). Only reachable in
    // dev-auth mode — structurally unreachable in prod.
    if (DebugMembershipOverride.deniesAll) {
      return Right(devAuthDeniedMembership(seasonId));
    }
    return Right(devAuthMembership(seasonId));
  }
  final repo = MembershipRepository(
    BreakdownApi(dio: ref.watch(apiDioProvider)),
  );
  return repo.fetch(seasonId);
}

/// The STABLE provider key for [seriesMembershipForCostume] (issue #535
/// review): only the inputs the series resolution actually depends on — the
/// costume id and its container candidates (character ∪ repertoire). NOT the
/// full [CostumeView]: a detail reload after every photo command produces a
/// new view (bumped `version`, refreshed `photos`), and keying on it would
/// re-run the character/season/membership chain per command.
///
/// The key is a Dart record of SCALAR fields (structural `==`), so the
/// generated family dedupes correctly across detail reloads. NOTE: no list
/// fields — a fresh `List` would break record equality by identity.
typedef CostumeMembershipScope = ({
  String costumeId,
  String? characterId,
  // First repertoire season (season_id-ordered server-side) — the only
  // repertoire input the resolution uses (deterministic first-season
  // pick). `null` = no repertoire binding.
  String? repertoireSeasonId,
});

CostumeMembershipScope costumeMembershipScope(CostumeView costume) => (
  costumeId: costume.id,
  characterId: costume.characterId,
  repertoireSeasonId: costume.seasonIds.isEmpty
      ? null
      : costume.seasonIds.first,
);

/// The series-level membership fetch for a **costume** (issue #535 review):
/// the client-side AUTHZ-GATE source for the **series-scoped costume-photo
/// policy** (ADR-035 B2/S2), keyed by [costumeMembershipScope] — mirroring the
/// server's resolution (character-first, repertoire fallback, unassigned
/// costume → first repertoire season, no resolvable container → error),
/// NOT the currently open season: a carried-over costume opened through a
/// repertoire season of a different series must gate on the costume's own
/// series, or the client would deny callers the server permits (and vice
/// versa).
///
/// Resolution order (mirror of `series_id_for_costume_strict`, api edge):
/// 1. `characterId != null` → `GET /v1/characters/{id}` → the character's
///    season → the season's series (D1 read path).
/// 2. else `seasonIds` (repertoire, ordered by `season_id` server-side) →
///    first season → the season's series (same deterministic first-season
///    pick the server makes).
/// 3. else — no character, no repertoire — `Left('costume.container-unresolved')`:
///    the gate stays pending-disabled; the server would answer 422 with the
///    same code (the photo affordances never render as a 403 narrative).
///
/// Dev-auth mode short-circuits to the permissive (or overridden-denial)
/// series membership without any network call.
@Riverpod(keepAlive: false)
Future<Result<SeriesMembershipDto>> seriesMembershipForCostume(
  Ref ref,
  CostumeMembershipScope scope,
) async {
  final config = ref.watch(appConfigProvider);
  if (config.devAuthMode) {
    // Dev-auth short-circuit: no resolution runs, so there is no real series
    // id — use the documented placeholder (never a costume id, which would
    // poison the DTO's `seriesId` field with a costume identifier).
    const devSeriesId = 'dev-auth-series';
    if (DebugMembershipOverride.deniesAll) {
      return Right(devAuthDeniedSeriesMembership(devSeriesId));
    }
    return Right(devAuthSeriesMembership(devSeriesId));
  }
  // Mirror the server's character-first resolution (issue #535 review).
  final characterId = scope.characterId;
  if (characterId != null) {
    try {
      final response = await BreakdownApi(dio: ref.watch(apiDioProvider))
          .getHandlersApi()
          .getCharacter(id: characterId);
      final character = response.data;
      if (character == null) {
        return const Left(ProblemError(code: 'character.dto_invalid'));
      }
      return await _seriesMembershipForSeason(ref, character.seasonId);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }
  // Unassigned costume: the repertoire fallback — the DTO's `season_ids`
  // are ordered by `season_id` server-side, matching the server's
  // deterministic first-season pick (carried in the scope key).
  final repertoireSeason = scope.repertoireSeasonId;
  if (repertoireSeason == null) {
    return const Left(ProblemError(code: 'costume.container-unresolved'));
  }
  return _seriesMembershipForSeason(ref, repertoireSeason);
}

/// Season → series membership resolution via the D1 read path (Drift cache
/// first, network GET `/v1/seasons/{id}` + upsert on miss), then
/// `GET /v1/series/{seriesId}/membership`. Shared by
/// [seriesMembershipForCostume] (character season and repertoire seasons
/// alike — the character's season may be a *different* season than the open
/// one, so the costume-keyed gate cannot shortcut through the open screen).
Future<Result<SeriesMembershipDto>> _seriesMembershipForSeason(
  Ref ref,
  String seasonId,
) async {
  final seasonRepo = ref.watch(seasonRepositoryProvider);
  final seasons = await seasonRepo.readCached();
  SeasonView? cached;
  if (seasons.isRight()) {
    for (final row in seasons.getOrElse((_) => const <SeasonView>[])) {
      if (row.id == seasonId) {
        cached = row;
        break;
      }
    }
  }
  final season = cached != null
      ? Right<ProblemError, SeasonView>(cached)
      : await seasonRepo.getAndCache(seasonId);
  return season.match(
    (err) => Left(err),
    (view) =>
        MembershipRepository(BreakdownApi(dio: ref.watch(apiDioProvider)))
            .fetchSeries(view.seriesId),
  );
}

/// The client-side AUTHZ-GATE source (D2/D3).
///
/// `currentMembershipProvider(seasonId)` exposes an
/// `AsyncValue<SeasonMembershipDto>`:
/// - `AsyncLoading` — the gated action is disabled with a spinner, never
///   reported as forbidden (D3).
/// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
///   transient error, not a 403 narrative (D3).
/// - `AsyncData` — the resolved membership. A *resolved denial* is
///   `canUploadContinuityPhotos == false` (or the matching capability):
///   gated actions short-circuit client-side with a localized 403 narrative
///   keyed on the backend problem `code`, and never issue the request. The
///   server remains authoritative — a client `true` is a gate only.
@Riverpod(keepAlive: false)
class CurrentMembership extends _$CurrentMembership {
  @override
  AsyncValue<SeasonMembershipDto> build(String seasonId) {
    final fetch = ref.watch(membershipFetchProvider(seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<SeasonMembershipDto>.error(err, StackTrace.current),
        (dto) => AsyncValue<SeasonMembershipDto>.data(dto),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<SeasonMembershipDto>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<SeasonMembershipDto>.loading(),
    };
  }

  /// Retry affordance for the `AsyncError` state (D3): refreshes the fetch.
  Future<void> retry() async {
    ref.invalidate(membershipFetchProvider(seasonId));
    ref.invalidateSelf();
  }
}
