// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/oidc_client.dart';
import 'package:frontend_flutter/auth/oidc_discovery.dart';
import 'package:frontend_flutter/core/result.dart';

/// Scriptable [AuthorizationUi]: echoes the request `state` back onto the
/// canned redirect (like a real IdP), or returns the scripted platform
/// failure. Covers exactly the three platform failure modes from design.md
/// §3 — browser-launch, timeout, redirect-capture.
class FakeAuthorizationUi implements AuthorizationUi {
  FakeAuthorizationUi(this.scripted);

  Result<Uri> scripted;
  Uri? launchedUrl;

  @override
  Future<Result<Uri>> launch(Uri authorizationUrl) async {
    launchedUrl = authorizationUrl;
    return scripted.fold(Left.new, (uri) {
      final params = Map.of(uri.queryParameters);
      final state = authorizationUrl.queryParameters['state'];
      if (state != null) params['state'] = state;
      return Right(uri.replace(queryParameters: params));
    });
  }
}

/// [AuthorizationUi] that parks the launch on a [Completer] so widget tests
/// can observe the in-flight state before completing it.
class DeferredAuthorizationUi implements AuthorizationUi {
  DeferredAuthorizationUi() : _gate = Completer<Result<Uri>>();

  final Completer<Result<Uri>> _gate;
  Uri? launchedUrl;

  void complete(Result<Uri> result) => _gate.complete(result);

  @override
  Future<Result<Uri>> launch(Uri authorizationUrl) {
    launchedUrl = authorizationUrl;
    return _gate.future;
  }
}

/// Unsigned test ID token carrying [sub] (the client never verifies
/// signatures — `subFromIdToken` only decodes the payload for display).
String testIdToken(String sub) {
  final payload = base64Url.encode(utf8.encode('{"sub":"$sub"}'));
  return 'e30.$payload.sig';
}

/// Real [OidcClient] (state check included) over a stub token endpoint and
/// [ui]. The token endpoint answers a fixed grant for `user-1`.
OidcClient clientFor(AuthorizationUi ui) {
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'access_token': 'at-new',
              'refresh_token': 'rt-new',
              'id_token': testIdToken('user-1'),
              'expires_in': 3600,
            },
          ),
        ),
      ),
    );
  return OidcClient(
    dio: dio,
    discovery: const OidcDiscovery(
      issuer: 'https://idp.example',
      authorizationEndpoint: 'https://idp.example/auth',
      tokenEndpoint: 'https://idp.example/token',
    ),
    config: const OidcClientConfig(
      clientId: 'client',
      redirectUri: 'breakdown://redirect',
    ),
    authorizationUi: ui,
  );
}
