// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// Server size budget for report PDFs (default 25 MB, spec B1/D3).
///
/// Enforced **during** streaming in `report_cache.dart`: the moment the
/// byte counter exceeds the cap the transfer is cancelled via `CancelToken`,
/// the partial temp file is deleted, and the card returns to idle with the
/// localized `pdf.too_large` copy. No full document is ever resident in
/// memory and no unbounded buffering occurs.
const int kPdfMaxBytes = 25 * 1024 * 1024;

/// The three per-day PDF reports (spec B1 — day id is a real parameter
/// since backend issues #333/#334 landed).
enum ReportPdfKind {
  dispo('dispo', 'dispo.pdf'),
  shootDay('shoot-day', 'shoot-day.pdf'),
  plannedVsActual('planned-vs-actual', 'planned-vs-actual.pdf');

  const ReportPdfKind(this.urlSuffix, this.fileSuffix);

  /// Path suffix under `/v1/shooting-days/{id}/report/`.
  final String urlSuffix;

  /// File-name suffix for the shared document (`<day>-<suffix>`).
  final String fileSuffix;

  /// The wire path for [dayId] (used by the streaming interceptor match and
  /// by tests — never interpolated by hand in production; production
  /// dispatches via the generated per-day client methods only, D1).
  String pathFor(String dayId) => '/v1/shooting-days/$dayId/report/$urlSuffix';
}

/// User-visible share-file name for a fetched PDF (`<day>-<report>.pdf`).
///
/// Mirrors the backend `sanitize_pdf_filename` posture (alphanumeric + `-`
/// survive, everything else becomes `-`): the shared file lands under a
/// predictable name and no part of the blob enters the Drift cache.
String reportShareFileName({
  required String dayLabel,
  required ReportPdfKind kind,
}) {
  final safeDay = dayLabel.split('').map((c) {
    final code = c.codeUnitAt(0);
    final alnum =
        (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
    return (alnum || c == '-') ? c : '-';
  }).join();
  final trimmed = safeDay.isEmpty ? 'day' : safeDay;
  return '$trimmed-${kind.fileSuffix}';
}

/// Normalizes a transport/HTTP failure to a stable [ProblemError] code.
///
/// Contract (spec `flutter-reports-screen`): transport failures and HTTP
/// errors carry no backend problem `code`, so they are normalized to
/// `transport.*` and, for a code-less HTTP error, to `http.<status>`. A body
/// that IS an RFC 9457 problem document keeps its stable `code`.
/// Localization and tests key on exactly these codes; no path renders raw
/// exception text or server detail.
ProblemError normalizeReportError(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['code'] is String) {
    try {
      return ProblemError.fromJson(data);
    } on Object {
      // A malformed problem body (e.g. `status` carries a string) must not
      // escape the handler: fall back to the stable code + HTTP status.
      return ProblemError(
        code: data['code'] as String,
        status: e.response?.statusCode,
      );
    }
  }
  final status = e.response?.statusCode;
  if (status != null) {
    return ProblemError(code: 'http.$status', status: status);
  }
  return ProblemError(code: 'transport.${e.type.name}', detail: e.message);
}

/// Strict-parses a Soll-Ist report body into the generated DTO.
///
/// Unknown status/flag values from a future backend strict-reject with
/// `report.unknown_status`; a structurally unexpected DTO (null body,
/// missing required fields, wrong types) rejects with
/// `report.unknown_shape`. Never throws.
Result<SollIstReport> parseSollIstReport(Object? raw, Serializers serializers) {
  if (raw == null) {
    return const Left(ProblemError(code: 'report.unknown_shape'));
  }
  try {
    final report = serializers.deserializeWith(SollIstReport.serializer, raw);
    if (report == null) {
      return const Left(ProblemError(code: 'report.unknown_shape'));
    }
    return Right(report);
  } on Object catch (e) {
    return Left(strictParseError(e));
  }
}

/// Strict-parses a shoot-day (Ist) row list; same error contract as
/// [parseSollIstReport]. Unknown `status` enum values (e.g. a future
/// backend execution state) reject with `report.unknown_status`.
Result<List<ShootDayRow>> parseShootDayRows(
  Object? raw,
  Serializers serializers,
) {
  if (raw == null) {
    return const Left(ProblemError(code: 'report.unknown_shape'));
  }
  try {
    final rows = serializers.deserialize(
      raw,
      specifiedType: const FullType(BuiltList, [FullType(ShootDayRow)]),
    ) as BuiltList<ShootDayRow>?;
    if (rows == null) {
      return const Left(ProblemError(code: 'report.unknown_shape'));
    }
    return Right(rows.toList());
  } on Object catch (e) {
    return Left(strictParseError(e));
  }
}

/// Strict-parses a dispo (Soll) row list; same error contract as
/// [parseSollIstReport].
Result<List<DispoRow>> parseDispoRows(Object? raw, Serializers serializers) {
  if (raw == null) {
    return const Left(ProblemError(code: 'report.unknown_shape'));
  }
  try {
    final rows = serializers.deserialize(
      raw,
      specifiedType: const FullType(BuiltList, [FullType(DispoRow)]),
    ) as BuiltList<DispoRow>?;
    if (rows == null) {
      return const Left(ProblemError(code: 'report.unknown_shape'));
    }
    return Right(rows.toList());
  } on Object catch (e) {
    return Left(strictParseError(e));
  }
}

/// Maps a deserialization failure to the strict-parse error contract: an
/// unrecognized enum/flag/status string is `report.unknown_status`, anything
/// structural is `report.unknown_shape`. Never throws.
ProblemError strictParseError(Object e) {
  final text = e.toString();
  if (text.contains('SceneShootStatus') ||
      text.contains('unknown enum') ||
      text.contains('unknown_status')) {
    return const ProblemError(code: 'report.unknown_status');
  }
  return const ProblemError(code: 'report.unknown_shape');
}

/// Localized client-side copy for report failures, keyed on the stable
/// problem `code` (never the server's localized `detail`).
String reportErrorCopy(ProblemError error) => switch (error.code) {
  'report.unknown_status' =>
    'The report has an unrecognized format — update the app to view it.',
  'report.unknown_shape' =>
    'The report could not be read (${error.code}). Try again.',
  'pdf.too_large' => 'The PDF is too large to preview on this device.',
  'authz.denied' ||
  'auth.session_required' ||
  'domain.forbidden' ||
  'report.forbidden' => 'You do not have access to these reports.',
  'membership.pending' => 'Checking report access…',
  'membership.unavailable' =>
    'Access check failed — retry to load the reports.',
  'share.failed' => 'Sharing failed — the file was discarded. Try again.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the report was not loaded. Try again.',
  _ when error.code.startsWith('http.') =>
    'The report could not be loaded (${error.code}). Try again.',
  _ => 'The report could not be loaded (${error.code}).',
};
