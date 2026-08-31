// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// Client-side mirror of the `SeasonMembershipDto` wire contract (D2 — the
/// single source of truth for the client-side AUTHZ-GATE).
///
/// NOTE (contract status): the backend route
/// `GET /v1/seasons/{seasonId}/membership` does not exist in
/// `backend/openapi.yaml` yet; it is tracked as a follow-up backend change.
/// Until it lands, this DTO and `MembershipRepository` implement the agreed
/// D2 contract verbatim so the gate logic, mapping, and providers are final —
/// when the generated client gains the endpoint, `MembershipRepository`
/// switches to the generated types (AGENTS.md §3 — never hand-type responses)
/// and this mirror is deleted. Do NOT extend this model with fields the
/// backend contract does not define.
///
/// Wire shape (snake_case, per backend conventions):
/// ```
/// {
///   "season_id": "...",
///   "has_active_costume_role_in_season": true,
///   "capabilities": ["upload_continuity_photos", "assign_costumes"]
/// }
/// ```
///
/// `has_active_costume_role_in_season` is the backend-computed result of
/// `has_active_costume_role_in_season(season_id, sub)` — the client NEVER
/// re-implements that predicate (CQRS-boundary rule, AGENTS.md §1). The
/// capability list is derived server-side from the backend's boolean roles;
/// the client only consumes it.
enum Capability {
  uploadContinuityPhotos('upload_continuity_photos'),
  assignCostumes('assign_costumes');

  const Capability(this.wireName);

  /// The backend's snake_case enum value on the wire.
  final String wireName;

  static Capability? tryParse(String wireName) {
    for (final c in Capability.values) {
      if (c.wireName == wireName) return c;
    }
    return null;
  }
}

/// Membership/role state for the authenticated user in one season.
class SeasonMembershipDto {
  const SeasonMembershipDto({
    required this.seasonId,
    required this.hasActiveCostumeRoleInSeason,
    required this.capabilities,
  });

  /// The season this membership is scoped to (must equal the provider key).
  final String seasonId;

  /// Backend-computed `has_active_costume_role_in_season(season_id, sub)`.
  final bool hasActiveCostumeRoleInSeason;

  /// Server-derived capability list (from the backend's boolean roles).
  final Set<Capability> capabilities;

  /// Capability gates for the AUTHZ-GATE. These read the server-derived
  /// capability list; a client `true` is a gate decision only — the backend
  /// re-checks authorization on every gated handler (server authoritative).
  bool get canUploadContinuityPhotos =>
      capabilities.contains(Capability.uploadContinuityPhotos);

  bool get canAssignCostumes =>
      capabilities.contains(Capability.assignCostumes);

  /// Parses the wire DTO. Unknown capability strings are ignored (additive
  /// extension tolerance — newer servers may emit capabilities this client
  /// does not know).
  static Result<SeasonMembershipDto> parse(Map<String, dynamic> json) {
    final seasonId = json['season_id'];
    final hasRole = json['has_active_costume_role_in_season'];
    if (seasonId is! String || hasRole is! bool) {
      return const Left(ProblemError(code: 'membership.dto_invalid'));
    }
    final rawCaps = json['capabilities'];
    final caps = <Capability>{};
    if (rawCaps is List) {
      for (final raw in rawCaps) {
        final c = raw is String ? Capability.tryParse(raw) : null;
        if (c != null) caps.add(c);
      }
    }
    return Right(
      SeasonMembershipDto(
        seasonId: seasonId,
        hasActiveCostumeRoleInSeason: hasRole,
        capabilities: caps,
      ),
    );
  }
}
