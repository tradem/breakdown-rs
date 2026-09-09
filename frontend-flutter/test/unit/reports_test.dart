// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests (`flutter-reports` 1.3 + 1.4): report DTO strict-parse
// mappers (unknown status/flag → `Err` with `report.unknown_status` /
// `report.unknown_shape`), transport/error-code normalization
// (`transport.*`, `http.<status>`), PDF byte-cap abort, share-file naming,
// temp-cleanup on every non-save exit, and the PDF transport-wiring
// regression (the pinned-CA Dio reaches the generated `HandlersApi` PDF
// calls through `SceneShootRepository`). No Flutter imports.

import 'dart:io';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/report_cache.dart';
import 'package:frontend_flutter/data/report_models.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';

void main() {
  group('strict-parse mappers', () {
    test('null body rejects with report.unknown_shape', () {
      expect(parseSollIstReport(null, standardSerializers).isLeft(), isTrue);
      expect(parseShootDayRows(null, standardSerializers).isLeft(), isTrue);
      expect(parseDispoRows(null, standardSerializers).isLeft(), isTrue);
    });

    test('structurally unexpected DTO rejects with report.unknown_shape', () {
      final res = parseSollIstReport({
        'unexpected': 'structure',
      }, standardSerializers);
      expect(
        res.match((err) => err.code, (_) => 'unexpected-right'),
        'report.unknown_shape',
      );
    });

    test('unknown shoot status strict-rejects with report.unknown_status', () {
      final raw = [
        {
          'scene_id': 's-1',
          'status': 'BogusFutureStatus',
          'continuity_photo_ids': <Object?>[],
          'notes': <Object?>[],
        },
      ];
      final res = parseShootDayRows(raw, standardSerializers);
      expect(
        res.match((err) => err.code, (_) => 'unexpected-right'),
        'report.unknown_status',
      );
    });

    test('valid Soll-Ist DTO round-trips', () {
      final report = SollIstReport(
        (b) => b
          ..isFinal = true
          ..rows.replace([
            SollIstDiffRow(
              (r) => r
                ..sceneId = 's-1'
                ..missing = false
                ..moved = true
                ..reshotCandidate = false
                ..skipped = false,
            ),
          ]),
      );
      final raw = standardSerializers.serializeWith(
        SollIstReport.serializer,
        report,
      );
      final res = parseSollIstReport(raw, standardSerializers);
      expect(res.isRight(), isTrue);
      expect(
        res.match((_) => false, (r) => r.isFinal && r.rows.length == 1),
        isTrue,
      );
    });
  });

  group('transport/error-code normalization', () {
    RequestOptions opts(String path) => RequestOptions(path: path);

    test('RFC 9457 problem body keeps its stable code', () {
      const path = '/v1/shooting-days/d/report/soll-ist';
      final err = DioException(
        requestOptions: opts(path),
        response: Response(
          requestOptions: opts(path),
          statusCode: 403,
          data: {'code': 'authz.denied', 'title': 't', 'status': 403},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(normalizeReportError(err).code, 'authz.denied');
    });

    test('code-less HTTP error normalizes to http.<status>', () {
      const path = '/v1/shooting-days/d/report/soll-ist';
      final err = DioException(
        requestOptions: opts(path),
        response: Response(
          requestOptions: opts(path),
          statusCode: 404,
          data: 'not found',
        ),
        type: DioExceptionType.badResponse,
      );
      final normalized = normalizeReportError(err);
      expect(normalized.code, 'http.404');
      expect(normalized.status, 404);
    });

    test('connectivity failure normalizes to transport.*', () {
      const path = '/v1/shooting-days/d/report/soll-ist';
      final err = DioException(
        requestOptions: opts(path),
        type: DioExceptionType.connectionError,
        message: 'dns',
      );
      expect(normalizeReportError(err).code, 'transport.connectionError');
    });

    test(
      'malformed problem body falls back to code + status (never throws)',
      () {
        const path = '/v1/shooting-days/d/report/soll-ist';
        final err = DioException(
          requestOptions: opts(path),
          response: Response(
            requestOptions: opts(path),
            statusCode: 403,
            // `status` carries a string — ProblemError.fromJson would throw
            // a TypeError on `as int?`.
            data: {
              'code': 'authz.denied',
              'title': 't',
              'status': 'four-oh-three',
            },
          ),
          type: DioExceptionType.badResponse,
        );
        final normalized = normalizeReportError(err);
        expect(normalized.code, 'authz.denied');
        expect(normalized.status, 403);
      },
    );
  });

  group('PDF byte cap + share naming + temp cleanup', () {
    test(
      'oversized stream aborts with pdf.too_large and zero file writes',
      () async {
        final temp = await Directory.systemTemp.createTemp('reports-cap-');
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        final stream = Stream<List<int>>.fromIterable([
          [1, 2, 3, 4],
          [5, 6, 7, 8],
        ]);
        final res = await writePdfStreamToTemp(
          stream: stream,
          tempDir: temp,
          fileName: 'day-1-dispo.pdf',
          maxBytes: 5,
        );
        expect(
          res.match((err) => err.code, (_) => 'unexpected-right'),
          'pdf.too_large',
        );
        expect(await File('${temp.path}/day-1-dispo.pdf').exists(), isFalse);
        expect(await temp.list().toList(), isEmpty);
      },
    );

    test('byte-exact payload succeeds; share name sanitizes day label', () {
      expect(
        reportShareFileName(dayLabel: 'Day 1!/x', kind: ReportPdfKind.dispo),
        'Day-1--x-dispo.pdf',
      );
      expect(
        reportShareFileName(
          dayLabel: 'day-1',
          kind: ReportPdfKind.plannedVsActual,
        ),
        'day-1-planned-vs-actual.pdf',
      );
    });

    test('over-cap byte payload writes nothing', () async {
      final temp = await Directory.systemTemp.createTemp('reports-bytes-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final res = await writePdfBytesToTemp(
        bytes: [1, 2, 3, 4],
        tempDir: temp,
        fileName: 'day-1-shoot-day.pdf',
        maxBytes: 3,
      );
      expect(
        res.match((err) => err.code, (_) => 'unexpected-right'),
        'pdf.too_large',
      );
      expect(await temp.list().toList(), isEmpty);
    });

    test(
      'cancel while the stream is idle maps to transport.cancelled',
      () async {
        final temp = await Directory.systemTemp.createTemp('reports-cancel-');
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        // Dio terminates the stream when the caller cancels while idle: the
        // error surfaces in the catch block, not through the per-chunk check.
        final token = CancelToken();
        const path = '/v1/shooting-days/day-1/report/dispo.pdf';
        final res = await writePdfStreamToTemp(
          stream: Stream<List<int>>.error(
            DioException(
              requestOptions: RequestOptions(path: path),
              type: DioExceptionType.cancel,
            ),
          ),
          tempDir: temp,
          fileName: 'day-1-dispo.pdf',
          cancelToken: token,
        );
        expect(
          res.match((err) => err.code, (_) => 'unexpected-right'),
          'transport.cancelled',
        );
        expect(await temp.list().toList(), isEmpty);
      },
    );

    test('temp cleanup removes the file on every non-save exit', () async {
      final temp = await Directory.systemTemp.createTemp('reports-clean-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final ok = await writePdfBytesToTemp(
        bytes: [1, 2, 3],
        tempDir: temp,
        fileName: 'day-1-dispo.pdf',
      );
      final file = ok.match((_) => throw StateError('expected file'), (f) => f);
      expect(await file.exists(), isTrue);
      await deleteReportTemp(file);
      expect(await file.exists(), isFalse);
      // Deleting twice never throws.
      await deleteReportTemp(file);
    });

    test('null PDF payload fails closed with report.unknown_shape', () async {
      final temp = await Directory.systemTemp.createTemp('reports-null-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final res = await writePdfResponseDataToTemp(
        data: null,
        tempDir: temp,
        fileName: 'day-1-dispo.pdf',
      );
      expect(
        res.match((err) => err.code, (_) => 'unexpected-right'),
        'report.unknown_shape',
      );
    });
  });

  group('PDF transport wiring (1.4 regression)', () {
    test('only the three PDF routes match the streaming interceptor', () {
      expect(
        isPdfReportPath('/v1/shooting-days/day-1/report/dispo.pdf'),
        isTrue,
      );
      expect(
        isPdfReportPath('/v1/shooting-days/day-1/report/shoot-day.pdf'),
        isTrue,
      );
      expect(
        isPdfReportPath('/v1/shooting-days/day-1/report/planned-vs-actual.pdf'),
        isTrue,
      );
      expect(
        isPdfReportPath('/v1/shooting-days/day-1/report/soll-ist'),
        isFalse,
      );
      expect(isPdfReportPath('/v1/shooting-days/day-1/report/dispo'), isFalse);
      expect(isPdfReportPath('/v1/seasons'), isFalse);
    });

    test('pinned-CA Dio reaches the generated HandlersApi PDF call '
        'through SceneShootRepository', () async {
      String? seenResponseType;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
      // Same order as buildPinnedDio: streaming interceptor first, so the
      // generated no-`Options` PDF call is switched to stream before the
      // capture below observes it.
      dio.interceptors.add(PdfStreamingInterceptor());
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seenResponseType = options.responseType.toString();
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: ResponseBody(
                  Stream<Uint8List>.value(Uint8List.fromList([37, 80, 68, 70])),
                  200,
                  headers: {
                    'content-type': ['application/pdf'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final db = CacheDatabase();
      addTearDown(db.close);
      final repo = SceneShootRepository(
        BreakdownApi(dio: dio),
        SceneShootCacheDao(db),
      );
      final temp = await Directory.systemTemp.createTemp('reports-wire-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final res = await repo.dispoReportPdf('day-1', tempDir: temp);
      expect(seenResponseType, ResponseType.stream.toString());
      final file = res.match(
        (_) => throw StateError('expected file'),
        (f) => f,
      );
      expect(await file.readAsBytes(), [37, 80, 68, 70]);
      expect(file.path.endsWith('day-1-dispo.pdf'), isTrue);
    });
  });
}
