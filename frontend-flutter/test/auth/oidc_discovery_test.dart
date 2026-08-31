// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/oidc_discovery.dart';

/// Boots a throwaway HTTP server whose served body is swappable per test, so
/// `discoverOidc` runs against real transport behavior (status codes, JSON
/// bodies, connection failures).
class _DiscoveryServer {
  final HttpServer server;
  Map<String, dynamic> body = {};

  _DiscoveryServer._(this.server);

  String get base {
    final host = server.address.address == '127.0.0.1'
        ? '127.0.0.1'
        : server.address.address;
    return 'http://$host:${server.port}';
  }

  static Future<_DiscoveryServer> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final holder = _DiscoveryServer._(server);
    unawaited(
      server.forEach((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(holder.body));
        await req.response.close();
      }),
    );
    return holder;
  }

  Future<void> close() => server.close(force: true);
}

Map<String, dynamic> validDocFor(String base) => {
  'issuer': base,
  'authorization_endpoint': '$base/auth',
  'token_endpoint': '$base/token',
  'jwks_uri': '$base/jwks',
};

void main() {
  late _DiscoveryServer idp;
  late Dio dio;

  setUpAll(() async {
    idp = await _DiscoveryServer.start();
    idp.body = validDocFor(idp.base);
  });

  setUp(() => dio = Dio());
  tearDownAll(() => idp.close());

  test(
    'parses a well-formed document and keeps the endpoints (Ok branch)',
    () async {
      final result = await discoverOidc(dio, idp.base);
      final doc = result.fold((e) => throw e, (d) => d);
      expect(doc.issuer, idp.base);
      expect(doc.authorizationEndpoint, '${idp.base}/auth');
      expect(doc.tokenEndpoint, '${idp.base}/token');
      expect(doc.jwksUri, '${idp.base}/jwks');
    },
  );

  test('rejects an issuer mismatch (client pointed at wrong IdP)', () async {
    // Server serves a document whose issuer differs from the URL the client
    // was configured with.
    idp.body = validDocFor(idp.base).map(
      (k, v) => k == 'issuer'
          ? MapEntry(k, 'https://other-idp.example')
          : MapEntry(k, v),
    );
    try {
      final result = await discoverOidc(dio, idp.base);
      final err = result.fold((e) => e, (d) => throw 'expected Left');
      expect(err.code, 'oidc.issuer_mismatch');
    } finally {
      idp.body = validDocFor(idp.base);
    }
  });

  test('rejects a document missing required fields', () async {
    final doc = OidcDiscovery.fromJson({'issuer': 42});
    final err = doc.fold((e) => e, (d) => throw 'expected Left');
    expect(err.code, 'oidc.discovery_invalid');
  });

  test('maps a transport failure to a ProblemError (Err branch)', () async {
    final result = await discoverOidc(dio, 'http://127.0.0.1:9/x');
    final err = result.fold((e) => e, (d) => throw 'expected Left');
    expect(err.code, startsWith('transport.'));
  });
}
