// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
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

/// The series-level membership fetch (issue #535) — the client-side
/// AUTHZ-GATE source for the **series-scoped costume-photo policy**
/// (ADR-035 B2/S2). Keyed by [seasonId]: the season's owning series is
/// resolved through the season projection (the season → series link is the
/// only way a season-scoped screen can name the tenant; D1 read path —
/// Drift cache first, network GET `/v1/seasons/{id}` + upsert on miss),
/// then `GET /v1/series/{seriesId}/membership` answers the predicate.
///
/// Dev-auth mode short-circuits to the permissive (or overridden-denial)
/// series membership without any network call.
@Riverpod(keepAlive: false)
Future<Result<SeriesMembershipDto>> seriesMembershipForSeason(
  Ref ref,
  String seasonId,
) async {
  final config = ref.watch(appConfigProvider);
  if (config.devAuthMode) {
    if (DebugMembershipOverride.deniesAll) {
      return Right(devAuthDeniedSeriesMembership(seasonId));
    }
    return Right(devAuthSeriesMembership(seasonId));
  }
  // Resolve the season's series via the D1 read path.
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
