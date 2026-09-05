// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/token_store.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/src/network/auth_token_interceptor.dart';

import '../../features/seasons/seasons_test_fakes.dart';
import '../../auth/oidc_test_fakes.dart';

class _FailingTokenStore extends FakeTokenStore {
  _FailingTokenStore() : super(null);

  @override
  Future<Result<AuthTokens?>> read() async =>
      const Left(ProblemError(code: 'auth.token_store_read_failed'));
}

/// Issues one GET through [interceptor] and captures the outgoing headers.
Future<Map<String, dynamic>> headersThrough(
  Interceptor interceptor,
  String url,
) async {
  Map<String, dynamic>? captured;
  final dio = Dio()
    ..interceptors.addAll([
      interceptor,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = Map.of(options.headers);
          handler.resolve(Response(requestOptions: options, statusCode: 200));
        },
      ),
    ]);
  await dio.get(url);
  return captured!;
}

void main() {
  group('AuthTokenInterceptor', () {
    test('attaches the bearer token over https', () async {
      final store = FakeTokenStore(
        AuthTokens(
          accessToken: 'at-1',
          refreshToken: 'rt-1',
          idToken: testIdToken('user-1'),
        ),
      );
      final headers = await headersThrough(
        AuthTokenInterceptor(store),
        'https://api.example.com/v1/seasons',
      );
      expect(headers['Authorization'], 'Bearer at-1');
    });

    test('withholds the credential on cleartext http (CWE-319)', () async {
      final store = FakeTokenStore(
        AuthTokens(
          accessToken: 'at-1',
          refreshToken: 'rt-1',
          idToken: testIdToken('user-1'),
        ),
      );
      final headers = await headersThrough(
        AuthTokenInterceptor(store),
        'http://10.0.2.2:3000/v1/seasons',
      );
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('no session: no header, no throw', () async {
      final headers = await headersThrough(
        AuthTokenInterceptor(FakeTokenStore(null)),
        'https://api.example.com/v1/seasons',
      );
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('store failure proceeds without token, never throws', () async {
      final headers = await headersThrough(
        AuthTokenInterceptor(_FailingTokenStore()),
        'https://api.example.com/v1/seasons',
      );
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });
}
