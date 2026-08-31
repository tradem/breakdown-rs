// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/oidc_client.dart';
import 'package:frontend_flutter/auth/oidc_discovery.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';

/// The authorization-UI double: returns a canned redirect URI and records the
/// launched URL so tests can assert the PKCE/audience request parameters.
class _FakeAuthorizationUi implements AuthorizationUi {
  _FakeAuthorizationUi(this.redirect);

  Uri? launchedUrl;
  Result<Uri> redirect;

  @override
  Future<Result<Uri>> launch(Uri authorizationUrl) async {
    launchedUrl = authorizationUrl;
    return redirect;
  }
}

class _TokenEndpointServer {
  final HttpServer server;
  final Map<String, dynamic> tokenResponse;
  final List<Map<String, String>> capturedForms = [];

  _TokenEndpointServer._(this.server, this.tokenResponse);

  String get base {
    final host = server.address.address;
    return 'http://$host:${server.port}';
  }

  static Future<_TokenEndpointServer> start({
    int status = 200,
    Map<String, dynamic> tokenResponse = const {
      'access_token': 'at-new',
      'refresh_token': 'rt-new',
      'id_token': 'id-new',
      'expires_in': 3600,
    },
  }) async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final holder = _TokenEndpointServer._(server, tokenResponse);
    unawaited(
      server.forEach((req) async {
        if (req.uri.path == '/token') {
          final body = await utf8.decodeStream(req);
          holder.capturedForms.add(Uri(query: body).queryParameters);
          req.response.statusCode = status;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(tokenResponse));
          await req.response.close();
          return;
        }
        if (req.uri.path == '/.well-known/openid-configuration') {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'issuer': holder.base,
              'authorization_endpoint': '${holder.base}/auth',
              'token_endpoint': '${holder.base}/token',
            }),
          );
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      }),
    );
    return holder;
  }

  Future<void> close() => server.close(force: true);
}

OidcClientConfig get _config => const OidcClientConfig(
  clientId: 'breakdown-client',
  redirectUri: 'breakdown://oauth-redirect',
  audience: 'breakdown-api',
);

Future<OidcClient> _clientFor(
  _TokenEndpointServer idp,
  AuthorizationUi ui,
) async {
  final dio = Dio();
  final discovery = await discoverOidc(dio, idp.base);
  final doc = discovery.fold((e) => throw e, (d) => d);
  return OidcClient(
    dio: dio,
    discovery: doc,
    config: _config,
    authorizationUi: ui,
  );
}

void main() {
  late _TokenEndpointServer idp;

  setUpAll(() async => idp = await _TokenEndpointServer.start());
  tearDownAll(() => idp.close());

  group('authorize (authorization-code + PKCE, Task 1.1)', () {
    test('exchanges the code for tokens and persists nothing itself', () async {
      final ui = _FakeAuthorizationUi(
        Right(Uri.parse('breakdown://oauth-redirect?code=abc123')),
      );
      final client = await _clientFor(idp, ui);

      final result = await client.authorize();
      final tokens = result.fold((e) => throw e, (t) => t);
      expect(tokens.accessToken, 'at-new');
      expect(tokens.refreshToken, 'rt-new');
      expect(tokens.idToken, 'id-new');
      expect(tokens.expiresAt, isNotNull);
    });

    test('sends the S256 challenge + verifier in the token exchange', () async {
      final ui = _FakeAuthorizationUi(
        Right(Uri.parse('breakdown://oauth-redirect?code=abc123')),
      );
      final client = await _clientFor(idp, ui);
      await client.authorize();

      expect(idp.capturedForms, isNotEmpty);
      final form = idp.capturedForms.last;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'abc123');
      expect(form['client_id'], 'breakdown-client');
      expect(form['redirect_uri'], 'breakdown://oauth-redirect');
      expect(form['code_verifier'], hasLength(64));
    });

    test(
      'authorization URL carries code_challenge_method=S256 and audience',
      () async {
        final ui = _FakeAuthorizationUi(
          Right(Uri.parse('breakdown://oauth-redirect?code=c')),
        );
        final client = await _clientFor(idp, ui);
        await client.authorize();

        final url = ui.launchedUrl!;
        expect(url.queryParameters['response_type'], 'code');
        expect(url.queryParameters['code_challenge_method'], 'S256');
        expect(url.queryParameters['audience'], 'breakdown-api');
        expect(url.queryParameters['scope'], contains('openid'));
      },
    );

    test(
      'IdP error redirect maps to oidc.authorization_denied (Err branch)',
      () async {
        final ui = _FakeAuthorizationUi(
          Right(
            Uri.parse(
              'breakdown://oauth-redirect?error=access_denied'
              '&error_description=user+said+no',
            ),
          ),
        );
        final client = await _clientFor(idp, ui);
        final result = await client.authorize();
        final err = result.fold((e) => e, (_) => throw 'expected Left');
        expect(err.code, 'oidc.authorization_denied');
        expect(err.detail, contains('user said no'));
      },
    );

    test(
      'redirect without a code maps to oidc.redirect_missing_code',
      () async {
        final ui = _FakeAuthorizationUi(
          Right(Uri.parse('breakdown://oauth-redirect?state=x')),
        );
        final client = await _clientFor(idp, ui);
        final result = await client.authorize();
        expect(
          result.fold((e) => e.code, (_) => throw 'expected Left'),
          'oidc.redirect_missing_code',
        );
      },
    );

    test('a failed launch (transport) surfaces as Err', () async {
      final ui = _FakeAuthorizationUi(
        const Left(ProblemError(code: 'oidc.browser_unavailable')),
      );
      final client = await _clientFor(idp, ui);
      final result = await client.authorize();
      expect(
        result.fold((e) => e.code, (_) => throw 'expected Left'),
        'oidc.browser_unavailable',
      );
    });

    test(
      'token endpoint failure maps to a ProblemError (Err branch)',
      () async {
        final failing = await _TokenEndpointServer.start(
          status: 400,
          tokenResponse: const {
            'error': 'invalid_grant',
            'error_description': 'code expired',
          },
        );
        try {
          final ui = _FakeAuthorizationUi(
            Right(Uri.parse('breakdown://oauth-redirect?code=stale')),
          );
          final client = await _clientFor(failing, ui);
          final result = await client.authorize();
          final err = result.fold((e) => e, (_) => throw 'expected Left');
          expect(err.code, startsWith('transport.'));
          expect(err.status, 400);
        } finally {
          await failing.close();
        }
      },
    );
  });

  group('refresh (Task 1.3 — online-first, no offline queue)', () {
    test('refresh grant returns the rotated token set (Ok branch)', () async {
      final client = await _clientFor(
        idp,
        _FakeAuthorizationUi(Right(Uri.parse('breakdown://x'))),
      );
      final result = await client.refresh('rt-old');
      final tokens = result.fold((e) => throw e, (t) => t);
      expect(tokens.accessToken, 'at-new');
      expect(tokens.refreshToken, 'rt-new');
      final form = idp.capturedForms.last;
      expect(form['grant_type'], 'refresh_token');
      expect(form['refresh_token'], 'rt-old');
    });

    test(
      'a refresh grant response without refresh_token keeps the old one',
      () async {
        final noRotate = await _TokenEndpointServer.start(
          tokenResponse: const {
            'access_token': 'at-2',
            'id_token': 'id-2',
            'expires_in': 60,
          },
        );
        try {
          final client = await _clientFor(
            noRotate,
            _FakeAuthorizationUi(Right(Uri.parse('breakdown://x'))),
          );
          final result = await client.refresh('rt-presented');
          final tokens = result.fold((e) => throw e, (t) => t);
          expect(tokens.refreshToken, 'rt-presented');
        } finally {
          await noRotate.close();
        }
      },
    );
  });
}
