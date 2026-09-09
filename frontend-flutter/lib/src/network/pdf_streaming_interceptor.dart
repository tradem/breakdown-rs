// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:dio/dio.dart';

/// Matches the three per-day PDF report paths
/// (`/v1/shooting-days/{id}/report/*.pdf`).
bool isPdfReportPath(String path) =>
    RegExp(r'/v1/shooting-days/[^/]+/report/[^/]+\.pdf').hasMatch(path);

/// Path-keyed interceptor that switches the PDF report routes to streaming.
///
/// The generated PDF methods (`dispoReportPdf`, `shootDayReportPdf`,
/// `plannedVsActualReportPdf`) accept no `Options` parameter, so
/// `ResponseType.stream` cannot be passed per call. This interceptor — wired
/// into the pinned-CA Dio in `buildPinnedDio` — sets
/// `responseType = ResponseType.stream` for the PDF routes so the repository
/// can consume `response.data` as a Dio `ResponseBody` stream and write each
/// chunk straight to the cache/temp file while counting bytes.
///
/// Lives in `src/network` (transport-owned), not in `data/`: the pinned Dio
/// is built here and `data/` may depend on `src/network` (established
/// direction), but `src/network` must not depend on `data/` — moving it out
/// of `report_cache.dart` removes that dependency cycle.
///
/// Installed unconditionally: it only touches PDF report paths and leaves
/// every other request (JSON report routes included) on the default JSON
/// response type.
class PdfStreamingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isPdfReportPath(options.path)) {
      options.responseType = ResponseType.stream;
    }
    handler.next(options);
  }
}
