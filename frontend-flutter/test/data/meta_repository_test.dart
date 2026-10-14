// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Tier-1 unit test: pure data-layer logic, no Flutter imports (AGENTS.md test
// pyramid, issue #656). Verifies that `MetaRepository.versions` returns the
// decoded `MetaVersionsResponse` on success and maps a server rejection
// (401 problem+json) to a `ProblemError` value — never a thrown exception.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/meta_repository.dart';

/// Interceptor that short-circuits the request without any real network call,
/// resolving with a canned [payload] or rejecting with [exception].
class _FakeMetaInterceptor extends Interceptor {
  _FakeMetaInterceptor({this.payload, this.exception})
    : assert(payload != null || exception != null);

  final Object? payload;
  final DioException? exception;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (exception != null) {
      handler.reject(exception!);
      return;
    }
    handler.resolve(
      Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: payload,
      ),
    );
  }
}

BreakdownApi _apiWith(Interceptor interceptor) =>
    BreakdownApi(dio: Dio(), interceptors: [interceptor]);

/// Raw wire payload exactly as the backend serializes it — the generated
/// client decodes it through the built_value serializer before [run] sees it.
Map<String, dynamic> get _versionsJson => {
  'api': '0.26.0',
  'core': '0.28.0',
  'infra': '0.33.0',
};

void main() {
  group('MetaRepository.versions (issue #656)', () {
    test('returns the decoded crate versions on success', () async {
      final repo = MetaRepository(
        _apiWith(_FakeMetaInterceptor(payload: _versionsJson)),
      );

      final result = await repo.versions();

      expect(result.isRight(), isTrue);
      result.fold((l) => fail('expected Right but got Left($l)'), (r) {
        expect(r.api, '0.26.0');
        expect(r.core, '0.28.0');
        expect(r.infra, '0.33.0');
      });
    });

    test('maps an unauthenticated rejection to a Left(ProblemError)', () async {
      // The route is Authenticated (change-proposal decision): a stale or
      // missing token answers 401 problem+json — the About screen must see
      // an error VALUE, never a thrown exception.
      final path = '/v1/meta/versions';
      final exception = DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 401,
          data: {
            'code': 'auth.unauthenticated',
            'title': 'Authentication required',
            'status': 401,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = MetaRepository(
        _apiWith(_FakeMetaInterceptor(exception: exception)),
      );

      final result = await repo.versions();

      expect(result.isLeft(), isTrue);
      result.fold(
        (l) => expect(l, isA<ProblemError>()),
        (r) => fail('expected Left but got Right($r)'),
      );
      result.fold(
        (l) => expect(l.code, 'auth.unauthenticated'),
        (_) => fail('expected Left'),
      );
    });
  });
}
