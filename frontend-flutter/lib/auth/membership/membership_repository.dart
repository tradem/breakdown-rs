// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';
import 'season_membership.dart';

/// Reads the season-scoped membership projection that backs the
/// client-side AUTHZ-GATE (D2 — one endpoint, no cross-projection
/// reconstruction; CQRS-boundary rule).
///
/// Contract status: `GET /v1/seasons/{seasonId}/membership` is not in
/// `backend/openapi.yaml` yet (follow-up backend change). Until the generated
/// client gains the endpoint, this repository performs the call directly on
/// the pinned Dio and parses [SeasonMembershipDto] — the wire contract is
/// frozen by D2, so switching to generated types later is a drop-in
/// replacement inside this class.
class MembershipRepository {
  const MembershipRepository(this._dio);

  final Dio _dio;

  /// Fetches the membership DTO for [seasonId].
  ///
  /// Never throws (no-throw rule, AGENTS.md §5): every failure — transport
  /// error, non-2xx with an RFC 9457 problem document, malformed body — is a
  /// `Left(ProblemError)` carrying the backend's stable `code` (the UI
  /// localizes from `code`, never from `detail`).
  Future<Result<SeasonMembershipDto>> fetch(String seasonId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/seasons/$seasonId/membership',
        options: Options(responseType: ResponseType.json),
      );
      final body = response.data;
      if (body == null) {
        return const Left(ProblemError(code: 'membership.dto_invalid'));
      }
      return SeasonMembershipDto.parse(body);
    } on DioException catch (e) {
      // A forbidden/missing season arrives as problem+json with a stable
      // code (e.g. `season.not_found`); transport failures surface under the
      // `transport.*` pseudo-namespace. Both are error states for the
      // provider (D3) — neither is a resolved denial.
      return Left(problemErrorFromDio(e));
    }
  }
}
