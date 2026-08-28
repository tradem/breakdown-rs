// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:dio/dio.dart';

/// A typed client-side representation of an RFC 9457 problem document
/// (ADR-031 D1). The backend emits one for every error response (status ≥ 400).
///
/// The contract the client branches on is [code] — a stable
/// `{context}.{reason}` machine identity. Never branch on [detail] or [title;
/// those are human-readable and localized server-side (the client localizes its
/// own copy keyed on [code]). [traceId] correlates with the server's otel span.
class ProblemError {
  const ProblemError({
    required this.code,
    this.title,
    this.detail,
    this.status,
    this.traceId,
  });

  /// Stable machine identity, e.g. `season.not_found`.
  final String code;

  /// Constant, never-localized English title (cacheable, spec-stable).
  final String? title;

  /// Human-readable explanation; localized server-side (Tranche 3).
  final String? detail;

  /// Canonical HTTP status of the problem.
  final int? status;

  /// otel trace id for server-side correlation.
  final String? traceId;

  /// Parses an RFC 9457 problem document. Returns `null` when the body is not a
  /// problem document, so callers can fall back to a transport-level error.
  factory ProblemError.fromJson(Map<String, dynamic> json) {
    return ProblemError(
      code: json['code'] as String? ?? 'unknown',
      title: json['title'] as String?,
      detail: json['detail'] as String?,
      status: json['status'] as int?,
      traceId: json['trace_id'] as String?,
    );
  }

  @override
  String toString() => 'ProblemError($code${status != null ? ' [$status]' : ''})';
}

/// Maps a [DioException] to a [ProblemError].
///
/// When the response body is an RFC 9457 problem document, its stable [code] is
/// surfaced. Otherwise a transport-level error is reported under the
/// `transport.*` pseudo-namespace so the caller can still branch on [code].
ProblemError problemErrorFromDio(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['code'] is String) {
    return ProblemError.fromJson(data);
  }
  return ProblemError(
    code: 'transport.${e.type.name}',
    detail: e.message,
    status: e.response?.statusCode,
  );
}
