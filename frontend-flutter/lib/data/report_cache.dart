// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'report_models.dart';

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

/// Streams a PDF byte stream to a temp file with a bounded byte cap.
///
/// The document is written chunk-by-chunk to [tempDir]/[fileName] (never the
/// persistent documents directory, never Drift) while counting bytes. The
/// moment the counter exceeds [maxBytes] the transfer is cancelled via
/// [cancelToken] (when supplied), the partial file is deleted, and the
/// caller gets `Left(pdf.too_large)` — no full document is ever resident in
/// memory and no unbounded buffering occurs.
///
/// A user cancellation surfaces as `Left(transport.cancelled)`; a stream
/// error as `Left(transport.network)`. In both cases no partial file is
/// left behind. [tempDir] is created when missing. Never throws: every
/// failure maps to a `Left(ProblemError)`.
Future<Result<File>> writePdfStreamToTemp({
  required Stream<List<int>> stream,
  required Directory tempDir,
  required String fileName,
  int maxBytes = kPdfMaxBytes,
  CancelToken? cancelToken,
}) async {
  try {
    await tempDir.create(recursive: true);
  } on Object {
    return const Left(ProblemError(code: 'transport.network'));
  }
  final file = File('${tempDir.path}/$fileName');
  IOSink? sink;
  try {
    sink = file.openWrite();
  } on Object {
    return const Left(ProblemError(code: 'transport.network'));
  }
  var bytes = 0;
  try {
    await for (final chunk in stream) {
      if (cancelToken?.isCancelled ?? false) {
        await sink.close();
        await _deleteQuietly(file);
        return const Left(ProblemError(code: 'transport.cancelled'));
      }
      bytes += chunk.length;
      if (bytes > maxBytes) {
        cancelToken?.cancel();
        await sink.close();
        await _deleteQuietly(file);
        return const Left(ProblemError(code: 'pdf.too_large'));
      }
      sink.add(chunk);
    }
    await sink.close();
    return Right(file);
  } on Object {
    try {
      await sink.close();
    } on Object {
      // Ignore close failures — the delete below is what matters.
    }
    await _deleteQuietly(file);
    return const Left(ProblemError(code: 'transport.network'));
  }
}

/// Writes an already-materialized PDF payload (the non-streaming fallback
/// shape) to a temp file under the same byte-cap contract as
/// [writePdfStreamToTemp]. Payloads over [maxBytes] reject with
/// `Left(pdf.too_large)` and write nothing.
Future<Result<File>> writePdfBytesToTemp({
  required List<int> bytes,
  required Directory tempDir,
  required String fileName,
  int maxBytes = kPdfMaxBytes,
}) {
  if (bytes.length > maxBytes) {
    return Future.value(const Left(ProblemError(code: 'pdf.too_large')));
  }
  return writePdfStreamToTemp(
    stream: Stream<List<int>>.value(bytes),
    tempDir: tempDir,
    fileName: fileName,
    maxBytes: maxBytes,
  );
}

/// Consumes the `data` payload of a generated PDF client response and
/// persists it to a temp file under the byte-cap contract.
///
/// Shapes handled (the generated methods return `Response<void>`, so the
/// payload is extracted by the caller and passed as [data]):
/// - Dio `ResponseBody` (the streaming shape once [PdfStreamingInterceptor]
///   is wired): chunked straight to the temp file.
/// - `Stream<List<int>>`: same streaming path (test seam).
/// - `List<int>`: bounded single write.
/// - `null`: the body was discarded (interceptor missing) — fail closed
///   with `report.unknown_shape` rather than silently succeeding with an
///   empty document.
/// - anything else: `report.unknown_shape`.
Future<Result<File>> writePdfResponseDataToTemp({
  required Object? data,
  required Directory tempDir,
  required String fileName,
  int maxBytes = kPdfMaxBytes,
  CancelToken? cancelToken,
}) {
  if (data is ResponseBody) {
    return writePdfStreamToTemp(
      stream: data.stream,
      tempDir: tempDir,
      fileName: fileName,
      maxBytes: maxBytes,
      cancelToken: cancelToken,
    );
  }
  if (data is Stream<List<int>>) {
    return writePdfStreamToTemp(
      stream: data,
      tempDir: tempDir,
      fileName: fileName,
      maxBytes: maxBytes,
      cancelToken: cancelToken,
    );
  }
  if (data is List<int>) {
    return writePdfBytesToTemp(
      bytes: data,
      tempDir: tempDir,
      fileName: fileName,
      maxBytes: maxBytes,
    );
  }
  return Future.value(const Left(ProblemError(code: 'report.unknown_shape')));
}

/// Best-effort temp-file cleanup: deletes [file] when it exists, never
/// throws. Called on every non-save exit — preview closed, share cancelled
/// or failed, byte-cap abort, or transport error — so no partial artifact is
/// ever left in the temp directory.
Future<void> deleteReportTemp(File file) => _deleteQuietly(file);

void _deleteQuietlySync(File file) {
  try {
    if (file.existsSync()) {
      file.deleteSync();
    }
  } on Object {
    // Cleanup is best-effort by contract.
  }
}

Future<void> _deleteQuietly(File file) async {
  // Synchronous internals: awaited dart:io deadlocks in the testWidgets
  // FakeAsync zone, so cleanup must never suspend on real IO. Production
  // behavior is unchanged (single-file delete, microseconds).
  _deleteQuietlySync(file);
}
