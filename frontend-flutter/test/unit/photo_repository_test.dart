// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

// Tier-1 unit test: pure data-layer logic, no Flutter imports (AGENTS.md test
// pyramid). Verifies that `PhotoRepository.getBytes` preserves and returns the
// fetched photo variant bytes (a `Uint8List` from the generated binary
// response) and maps a server rejection to a `ProblemError` value.

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/photo_repository.dart';

/// Interceptor that short-circuits the request without any real network call,
/// resolving with canned [bytes] or rejecting with [exception].
class _FakePhotoBytesInterceptor extends Interceptor {
  _FakePhotoBytesInterceptor({this.bytes, this.exception})
    : assert(bytes != null || exception != null);

  final Uint8List? bytes;
  final DioException? exception;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (exception != null) {
      handler.reject(exception!);
      return;
    }
    handler.resolve(
      Response<Uint8List>(
        requestOptions: options,
        statusCode: 200,
        data: bytes,
      ),
    );
  }
}

BreakdownApi _apiWith(Interceptor interceptor) =>
    BreakdownApi(dio: Dio(), interceptors: [interceptor]);

void main() {
  group('PhotoRepository.getBytes', () {
    test('returns the fetched photo bytes on success', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final repo = PhotoRepository(
        _apiWith(_FakePhotoBytesInterceptor(bytes: bytes)),
      );

      final result = await repo.getBytes('costume-1', 'photo-1', 'original');

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('expected Right but got Left($l)'),
        (r) => expect(r, bytes),
      );
    });

    test('maps a server rejection to a Left(ProblemError)', () async {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/v1/costumes/c/photos/p/bytes'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/costumes/c/photos/p/bytes'),
          statusCode: 403,
          data: {
            'code': 'photo.forbidden',
            'title': 'Not authorized',
            'status': 403,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = PhotoRepository(
        _apiWith(_FakePhotoBytesInterceptor(exception: exception)),
      );

      final result = await repo.getBytes('c', 'p', 'original');

      expect(result.isLeft(), isTrue);
      result.fold(
        (l) => expect(l, isA<ProblemError>()),
        (r) => fail('expected Left but got Right($r)'),
      );
      result.fold(
        (l) => expect(l.code, 'photo.forbidden'),
        (_) => fail('expected Left'),
      );
    });
  });
}
