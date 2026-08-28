// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

// Regression test for per-flavor CA pinning (issue #301 / AGENTS.md §5 /
// ADR-024). It spins up a local HTTPS server whose leaf certificate is signed
// by `ca_unpinned`, then asserts that a client pinned ONLY to `ca_pinned`
// rejects the connection (a certificate signed by a different, unpinned CA is
// refused), while a client pinned to `ca_unpinned` (the actual signer) is
// accepted.
//
// Runs on the host Dart VM under `flutter test` (uses `dart:io`).

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/src/network/api_client.dart';

const _fixtures = 'test/fixtures/certs';

Future<SecurityContext> _serverContext() async => SecurityContext()
  ..useCertificateChainBytes(
    await File('$_fixtures/server_unpinned.pem').readAsBytes(),
  )
  ..usePrivateKeyBytes(
    await File('$_fixtures/server_unpinned.key').readAsBytes(),
  );

Dio _pinnedClient(String caPemFile) {
  final ctx = pinnedSecurityContext(
    File('$_fixtures/$caPemFile').readAsBytesSync(),
  );
  final dio = Dio();
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient(context: ctx),
  );
  return dio;
}

void main() {
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    server = await HttpServer.bindSecure(
      '127.0.0.1',
      0,
      await _serverContext(),
    );
    server.listen((req) {
      req.response
        ..statusCode = 200
        ..write('ok')
        ..close();
    });
    baseUrl = 'https://127.0.0.1:${server.port}';
  });

  tearDownAll(() => server.close());

  test('rejects a certificate signed by an unpinned CA', () async {
    // Client trusts ONLY ca_pinned; the server cert is signed by ca_unpinned
    // (a different CA). The pinned context must refuse it because the signer
    // is not the pinned CA.
    final dio = _pinnedClient('ca_pinned.pem');
    await expectLater(dio.get(baseUrl), throwsA(isA<DioException>()));
  });

  test('accepts a certificate chained to the pinned CA', () async {
    // Pin to the CA that actually signed the server cert.
    final dio = _pinnedClient('ca_unpinned.pem');
    final resp = await dio.get(baseUrl);
    expect(resp.statusCode, 200);
    expect(resp.data, 'ok');
  });
}
