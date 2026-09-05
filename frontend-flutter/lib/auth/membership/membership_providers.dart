// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/result.dart';
import '../../src/network/api_client.dart';
import '../auth_providers.dart';
import 'capability.dart';
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
    return Right(devAuthMembership(seasonId));
  }
  final repo = MembershipRepository(
    BreakdownApi(dio: ref.watch(apiDioProvider)),
  );
  return repo.fetch(seasonId);
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
