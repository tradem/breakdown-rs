// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

// Tier-1 unit test: pure logic, no Flutter imports (AGENTS.md test pyramid).
// Exercises the RFC 9457 problem+json parsing and the DioException -> ProblemError
// mapping in isolation.

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/problem_error.dart';

void main() {
  group('ProblemError.fromJson', () {
    test('parses a full RFC 9457 problem document', () {
      final error = ProblemError.fromJson({
        'code': 'season.not_found',
        'title': 'Season not found',
        'detail': 'No season with id 42 exists.',
        'status': 404,
        'trace_id': 'abc123',
      });

      expect(error.code, 'season.not_found');
      expect(error.title, 'Season not found');
      expect(error.detail, 'No season with id 42 exists.');
      expect(error.status, 404);
      expect(error.traceId, 'abc123');
    });

    test('falls back to unknown code when code is absent', () {
      final error = ProblemError.fromJson({'status': 500});
      expect(error.code, 'unknown');
      expect(error.status, 500);
      expect(error.title, isNull);
    });

    test('toString includes code and status', () {
      final error = ProblemError(code: 'x.y', status: 409);
      expect(error.toString(), 'ProblemError(x.y [409])');
    });
  });

  group('problemErrorFromDio', () {
    test('maps a problem+json response body to ProblemError', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/seasons/42'),
        response: Response(
          requestOptions: RequestOptions(path: '/seasons/42'),
          statusCode: 404,
          data: {
            'code': 'season.not_found',
            'title': 'Season not found',
            'status': 404,
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final error = problemErrorFromDio(dioError);
      expect(error.code, 'season.not_found');
      expect(error.status, 404);
    });

    test('maps a non-problem response to a transport error', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/seasons'),
        response: Response(
          requestOptions: RequestOptions(path: '/seasons'),
          statusCode: 500,
          data: 'Internal Server Error', // not a problem document
        ),
        type: DioExceptionType.badResponse,
      );

      final error = problemErrorFromDio(dioError);
      expect(error.code, 'transport.badResponse');
      expect(error.status, 500);
    });

    test('maps a connection error to a transport error with no status', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/seasons'),
        type: DioExceptionType.connectionTimeout,
        message: 'timed out',
      );

      final error = problemErrorFromDio(dioError);
      expect(error.code, 'transport.connectionTimeout');
      expect(error.status, isNull);
      expect(error.detail, 'timed out');
    });
  });
}
