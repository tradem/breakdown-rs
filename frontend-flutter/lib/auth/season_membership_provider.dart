// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import '../data/cache/cache_ttl.dart';
import '../data/cache/seasons_cache_providers.dart';
import 'membership/capability.dart';
import 'membership/membership_providers.dart';

part 'season_membership_provider.g.dart';

/// TTL for the season-membership read: the chip must not refetch on every
/// navigation, but a role change should surface within minutes (design.md
/// §5). Pull-to-refresh invalidates explicitly regardless of TTL.
const Duration kMembershipTtl = Duration(minutes: 5);

/// Strictly parses the capabilities of a fetched [SeasonMembershipDto]
/// (design.md §5, `flutter-hierarchy-navigation` D6).
///
/// Every wire string must be a known [Capability]; an unknown entry rejects
/// the whole DTO as `Err` with the stable code
/// `authz.membership.capability_unknown` — the client never guesses policy
/// (the handshake rule for Phase 2+). Transport/fetch failures pass
/// through unchanged.
Result<SeasonMembershipDto> strictParseMembership(
  Result<SeasonMembershipDto> fetched,
) => fetched.flatMap((dto) {
  for (final wire in dto.capabilities) {
    if (Capability.tryParse(wire) == null) {
      return const Left(
        ProblemError(code: 'authz.membership.capability_unknown'),
      );
    }
  }
  return Right(dto);
});

/// TTL-scoped membership cache entry (client-only write time, same
/// discipline as the Drift `cachedAt` columns).
class SeasonMembershipEntry {
  const SeasonMembershipEntry({required this.value, required this.at});

  final Result<SeasonMembershipDto> value;
  final DateTime at;
}

/// TTL-scoped cache for the strict-parsed membership read (design.md §5).
/// KeepAlive by construction — the TTL window must survive screen disposal,
/// or every child navigation would refetch.
class SeasonMembershipCache
    extends Notifier<Map<String, SeasonMembershipEntry>> {
  @override
  Map<String, SeasonMembershipEntry> build() => const {};

  void store(String seasonId, Result<SeasonMembershipDto> value, DateTime at) {
    state = {...state, seasonId: SeasonMembershipEntry(value: value, at: at)};
  }

  void invalidate(String seasonId) {
    if (!state.containsKey(seasonId)) return;
    state = {...state}..remove(seasonId);
  }

  void clear() => state = const {};
}

final seasonMembershipCacheProvider =
    NotifierProvider<SeasonMembershipCache, Map<String, SeasonMembershipEntry>>(
      SeasonMembershipCache.new,
    );

/// Season-scoped membership read with strict capability parsing
/// (`flutter-hierarchy-navigation` 3.1).
///
/// Family provider over `GET /v1/seasons/{id}/membership` (via the existing
/// [membershipFetchProvider], so dev-auth short-circuit and the CURRENT
/// session wiring are reused): an unknown capability string rejects the DTO
/// as `Err` ([strictParseMembership]); fresh cache entries (younger than
/// [kMembershipTtl] per the injectable [clockProvider]) are served without
/// a network call so child navigation never refetches. Not keepAlive — the
/// TTL cache alongside it is.
///
/// Phase 1 uses this read for display (capabilities chip) only; gated
/// capability actions beyond it are future-phase concerns (D6).
@Riverpod(keepAlive: false)
Future<Result<SeasonMembershipDto>> seasonMembership(
  Ref ref,
  String seasonId,
) async {
  final cache = ref.watch(seasonMembershipCacheProvider);
  final clock = ref.watch(clockProvider);
  final entry = cache[seasonId];
  if (entry != null && !isRowExpired(entry.at, kMembershipTtl, clock: clock)) {
    return entry.value;
  }
  // Revalidate explicitly: the fetch provider is auto-dispose and may still
  // hold a stale completed future (its disposal is timer-scheduled); an
  // explicit invalidate guarantees a TTL-expired read hits the network
  // instead of reusing a pre-expiry response.
  ref.invalidate(membershipFetchProvider(seasonId));
  final fetched = await ref.watch(membershipFetchProvider(seasonId).future);
  final parsed = strictParseMembership(fetched);
  ref
      .read(seasonMembershipCacheProvider.notifier)
      .store(seasonId, parsed, clock.now());
  return parsed;
}
