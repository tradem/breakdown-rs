// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: hy3 (opencode-go)

import 'dart:convert';

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
    this.extensions,
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

  /// The problem's declared S0/S1 extension fields (ADR-031 D4), verbatim
  /// JSON. Callers branch on the stable `code` first and only read typed
  /// extensions of codes they know — e.g. `blocking_uncertainties` on
  /// `ai-import.apply-blocked` (issue #663).
  final Map<String, dynamic>? extensions;

  /// Parses an RFC 9457 problem document. Returns `null` when the body is not a
  /// problem document, so callers can fall back to a transport-level error.
  factory ProblemError.fromJson(Map<String, dynamic> json) {
    return ProblemError(
      code: json['code'] as String? ?? 'unknown',
      title: json['title'] as String?,
      detail: json['detail'] as String?,
      status: json['status'] as int?,
      traceId: json['trace_id'] as String?,
      extensions: json['extensions'] is Map<String, dynamic>
          ? json['extensions'] as Map<String, dynamic>
          : null,
    );
  }

  @override
  String toString() =>
      'ProblemError($code${status != null ? ' [$status]' : ''})';
}

/// Maps a [DioException] to a [ProblemError].
///
/// When the response body is an RFC 9457 problem document, its stable [code] is
/// surfaced. Otherwise a transport-level error is reported under the
/// `transport.*` pseudo-namespace so the caller can still branch on [code].
ProblemError problemErrorFromDio(DioException e) {
  final data = _decodeProblemBody(e.response?.data);
  if (data is Map<String, dynamic> && data['code'] is String) {
    return ProblemError.fromJson(data);
  }
  return ProblemError(
    code: 'transport.${e.type.name}',
    detail: e.message,
    status: e.response?.statusCode,
  );
}

/// Decodes a problem document that Dio handed back as **text**.
///
/// Callers that ask for `Response<String>` (the AI-import uploads: the success
/// body is a JSON string) receive the raw body text on an error status as well,
/// so the `Map` check above can never see the backend's problem `code` and every
/// 4xx/413 collapses into `transport.badResponse` — which the UI renders as
/// "network problem", hiding the real reason (observed: a refused
/// `ai-import.forbidden` upload looked like a connectivity failure while the
/// health checks were green). Decoding the text first keeps the stable `code`.
///
/// A body that is not a JSON object (a proxy's HTML error page, Axum's plain
/// `Failed to buffer …` text) stays as it is, so `transport.badResponse` keeps
/// meaning "the backend answered with something unusable".
Object? _decodeProblemBody(Object? data) {
  if (data is! String) return data;
  final text = data.trim();
  if (!text.startsWith('{')) return data;
  try {
    return jsonDecode(text);
  } on FormatException {
    return data;
  }
}
