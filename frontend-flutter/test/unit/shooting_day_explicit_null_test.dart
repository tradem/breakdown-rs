// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit test: pure data-layer logic, no Flutter imports (AGENTS.md test
// pyramid). Verifies that the raw-Dio explicit-null paths (#374, follow-up to
// backend #372) put a literal JSON `null` on the wire — the typed
// `UpdateShootingDayRequest` serializer omits null fields, so the backend
// would see an absent update field and reject with 422 — and that both
// `Ok` and `Err` branches of every `Result`-returning call are asserted.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';

/// Interceptor that short-circuits the request without any real network
/// call, asserting the raw PATCH shape and resolving with [data] (or
/// rejecting with [exception]).
class _FakeExplicitNullInterceptor extends Interceptor {
  _FakeExplicitNullInterceptor({required this.data, this.exception});

  final Object? data;
  final DioException? exception;

  Map<String, dynamic>? sentBody;
  String? sentPath;
  String? sentMethod;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    sentBody = options.data as Map<String, dynamic>?;
    sentPath = options.path;
    sentMethod = options.method;
    if (exception != null) {
      handler.reject(exception!);
      return;
    }
    handler.resolve(
      Response<Object>(requestOptions: options, statusCode: 200, data: data),
    );
  }
}

ShootingDayRepository _repoWith(_FakeExplicitNullInterceptor interceptor) {
  // The cache DAO is untouched by the raw PATCH path; a real in-memory Drift
  // database keeps the constructor honest without reaching the network.
  final db = CacheDatabase(NativeDatabase.memory());
  return ShootingDayRepository(
    BreakdownApi(dio: Dio(), interceptors: [interceptor]),
    ShootingDayCacheDao(db),
  );
}

void main() {
  group('ShootingDayRepository.unschedule (explicit date: null)', () {
    test('sends a literal null date and returns the echoed version', () async {
      final fake = _FakeExplicitNullInterceptor(data: 4);
      final repo = _repoWith(fake);

      final result = await repo.unschedule('d-1', version: 3);

      expect(fake.sentMethod, 'PATCH');
      expect(fake.sentPath, '/v1/shooting-days/d-1');
      // The whole point (issue #374): the key must be PRESENT with a null
      // value — absent means "no update" to the backend since #372.
      expect(fake.sentBody, containsPair('date', isNull));
      expect(fake.sentBody, containsPair('version', 3));
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('expected Right but got Left($l)'),
        (r) => expect(r, 4),
      );
    });

    test('maps a server rejection to a Left(ProblemError)', () async {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/v1/shooting-days/d-1'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/shooting-days/d-1'),
          statusCode: 409,
          data: {
            'code': 'shooting_day.version_conflict',
            'title': 'Conflict',
            'status': 409,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = _repoWith(
        _FakeExplicitNullInterceptor(data: null, exception: exception),
      );

      final result = await repo.unschedule('d-1', version: 3);

      expect(result.isLeft(), isTrue);
      result.fold((l) {
        expect(l, isA<ProblemError>());
        expect(l.code, 'shooting_day.version_conflict');
      }, (r) => fail('expected Left but got Right($r)'));
    });

    test('maps a non-int 200 body to shooting_day.dto_invalid', () async {
      final repo = _repoWith(
        _FakeExplicitNullInterceptor(
          data: <String, dynamic>{'unexpected': true},
        ),
      );

      final result = await repo.unschedule('d-1', version: 3);

      expect(result.isLeft(), isTrue);
      result.fold(
        (l) => expect(l.code, 'shooting_day.dto_invalid'),
        (r) => fail('expected Left but got Right($r)'),
      );
    });
  });

  group('ShootingDayRepository.renameToNull (explicit label: null)', () {
    test('sends a literal null label and returns the echoed version', () async {
      final fake = _FakeExplicitNullInterceptor(data: 5);
      final repo = _repoWith(fake);

      final result = await repo.renameToNull('d-2', version: 4);

      expect(fake.sentMethod, 'PATCH');
      expect(fake.sentPath, '/v1/shooting-days/d-2');
      expect(fake.sentBody, containsPair('label', isNull));
      expect(fake.sentBody, containsPair('version', 4));
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('expected Right but got Left($l)'),
        (r) => expect(r, 5),
      );
    });

    test('maps a server rejection to a Left(ProblemError)', () async {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/v1/shooting-days/d-2'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/shooting-days/d-2'),
          statusCode: 409,
          data: {
            'code': 'shooting_day.version_conflict',
            'title': 'Conflict',
            'status': 409,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = _repoWith(
        _FakeExplicitNullInterceptor(data: null, exception: exception),
      );

      final result = await repo.renameToNull('d-2', version: 4);

      expect(result.isLeft(), isTrue);
      result.fold((l) {
        expect(l, isA<ProblemError>());
        expect(l.code, 'shooting_day.version_conflict');
      }, (r) => fail('expected Left but got Right($r)'));
    });
  });
}
