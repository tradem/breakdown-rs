// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// Reads the season-scoped membership projection that backs the
/// client-side AUTHZ-GATE (D2 — one endpoint, no cross-projection
/// reconstruction; CQRS-boundary rule, AGENTS.md §1).
///
/// Consumes the generated `breakdown_api` client (AGENTS.md §3 — never
/// hand-type responses). The mirror DTO that predated the backend route was
/// deleted once `GET /v1/seasons/{seasonId}/membership` landed in
/// `backend/openapi.yaml` (issue #311) and the client was regenerated.
class MembershipRepository {
  const MembershipRepository(this._api);

  final BreakdownApi _api;

  /// Fetches the membership DTO for [seasonId].
  ///
  /// Never throws (no-throw rule, AGENTS.md §5): every failure — transport
  /// error, non-2xx with an RFC 9457 problem document, or a body the generated
  /// serializer cannot decode — is a `Left(ProblemError)` carrying the
  /// backend's stable `code` (the UI localizes from `code`, never from
  /// `detail`).
  Future<Result<SeasonMembershipDto>> fetch(String seasonId) async {
    try {
      final response = await _api.getHandlersApi().getSeasonMembership(
        id: seasonId,
      );
      final dto = response.data;
      if (dto == null) {
        return const Left(ProblemError(code: 'membership.dto_invalid'));
      }
      return Right(dto);
    } on DioException catch (e) {
      // A forbidden/missing season arrives as problem+json with a stable
      // code (e.g. `season.not_found`); transport failures surface under the
      // `transport.*` pseudo-namespace. Both are error states for the
      // provider (D3) — neither is a resolved denial.
      return Left(problemErrorFromDio(e));
    }
  }
}
