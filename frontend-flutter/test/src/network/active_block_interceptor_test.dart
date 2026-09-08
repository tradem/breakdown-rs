// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/src/network/active_block_interceptor.dart';

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
  group('ActiveBlockInterceptor', () {
    test('attaches X-Active-Block when a scope is set', () async {
      final headers = await headersThrough(
        const ActiveBlockInterceptor('block-1'),
        'https://api.example.com/v1/episodes?block_id=block-1',
      );
      expect(headers['X-Active-Block'], 'block-1');
    });

    test('omits the header when no scope is set', () async {
      final headers = await headersThrough(
        const ActiveBlockInterceptor(null),
        'https://api.example.com/v1/seasons',
      );
      expect(headers.containsKey('X-Active-Block'), isFalse);
    });

    test(
      'treats a blank id as unset (never sends a malformed header)',
      () async {
        final headers = await headersThrough(
          const ActiveBlockInterceptor(''),
          'https://api.example.com/v1/episodes?block_id=block-1',
        );
        expect(headers.containsKey('X-Active-Block'), isFalse);
      },
    );

    test('treats a whitespace-only id as unset (review)', () async {
      final headers = await headersThrough(
        const ActiveBlockInterceptor('   '),
        'https://api.example.com/v1/episodes?block_id=block-1',
      );
      expect(headers.containsKey('X-Active-Block'), isFalse);
    });

    test('never overwrites a caller-set header', () async {
      Map<String, dynamic>? captured;
      final dio = Dio()
        ..interceptors.addAll([
          const ActiveBlockInterceptor('block-1'),
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured = Map.of(options.headers);
              handler.resolve(
                Response(requestOptions: options, statusCode: 200),
              );
            },
          ),
        ]);
      await dio.get(
        'https://api.example.com/v1/episodes',
        options: Options(headers: {'X-Active-Block': 'pinned-in-test'}),
      );
      expect(captured!['X-Active-Block'], 'pinned-in-test');
    });
  });
}
