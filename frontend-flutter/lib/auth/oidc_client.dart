// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'oidc_discovery.dart';
import 'pkce.dart';
import 'token_store.dart';

/// Launches the system browser for the authorization request and resolves
/// with the redirect URI captured from the IdP (custom tab / deep link).
///
/// The platform wiring (Android Custom Tabs + app deep links) is injected at
/// the composition root; tests provide a fake. This abstraction keeps all
/// HTTP (token exchange, discovery) on the pinned-CA Dio while the browser
/// leg stays a platform concern.
abstract interface class AuthorizationUi {
  /// Opens [authorizationUrl] and completes when the IdP redirects back with
  /// the authorization response URI.
  Future<Result<Uri>> launch(Uri authorizationUrl);
}

/// Configuration for the OIDC client, sourced from `--dart-define` (never
/// hardcoded secrets — AGENTS.md §5). A client id is public by design
/// (PKCE, no client secret on a public native client).
class OidcClientConfig {
  const OidcClientConfig({
    required this.clientId,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email'],
    this.audience,
  });

  final String clientId;
  final String redirectUri;
  final List<String> scopes;

  /// Requested API audience, mirroring the backend's `OIDC_AUDIENCE`
  /// validation (ADR-018). Sent as an extra authorization parameter; the
  /// backend independently validates the token's `aud` claim.
  final String? audience;
}

/// The OIDC authorization-code + PKCE client (Tasks 1.1–1.3).
///
/// All HTTP goes over the caller-supplied [Dio], which in production is the
/// pinned-CA client from `buildApiClient` (D4 — IdP traffic is pinned too,
/// with the documented `DEV_IDP_INSECURE=1` dev-flavor exception applied by
/// the composition root when constructing this client's Dio).
///
/// Online-first (Task 1.3): refresh happens on demand via [refresh]; there is
/// no offline queue and no replay — a failed refresh is an `Err` the caller
/// must surface.
class OidcClient {
  const OidcClient({
    required this.dio,
    required this.discovery,
    required this.config,
    required this.authorizationUi,
  });

  final Dio dio;
  final OidcDiscovery discovery;
  final OidcClientConfig config;
  final AuthorizationUi authorizationUi;

  /// Runs the full authorization-code + PKCE flow and returns the tokens.
  ///
  /// A cryptographically random `state` is bound to the request and verified
  /// on the redirect (login-CSRF protection — the client must not accept an
  /// authorization response it did not initiate).
  Future<Result<AuthTokens>> authorize() async {
    final pkce = Pkce.generate();
    final state = _generateState();
    final params = {
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri,
      'scope': config.scopes.join(' '),
      'code_challenge': pkce.challenge,
      'code_challenge_method': Pkce.challengeMethod,
      'state': state,
      if (config.audience != null) 'audience': config.audience!,
    };
    final endpoint = Uri.tryParse(discovery.authorizationEndpoint);
    if (endpoint == null) {
      return const Left(ProblemError(code: 'oidc.discovery_invalid'));
    }

    final redirect = await authorizationUi.launch(
      endpoint.replace(queryParameters: params),
    );
    if (redirect.isLeft()) {
      return Left(redirect.getLeft().toNullable()!);
    }
    final codeResult = _extractCode(
      redirect.getRight().toNullable()!,
      expectedState: state,
    );
    if (codeResult.isLeft()) {
      return Left(codeResult.getLeft().toNullable()!);
    }

    return _tokenRequest({
      'grant_type': 'authorization_code',
      'code': codeResult.getRight().toNullable()!,
      'redirect_uri': config.redirectUri,
      'client_id': config.clientId,
      'code_verifier': pkce.verifier,
    });
  }

  /// Refresh grant (Task 1.3). Returns the rotated token set.
  ///
  /// [currentIdToken] is the ID token of the session being refreshed: an OIDC
  /// refresh response MAY omit `id_token` (the old one stays valid), in which
  /// case the presented token is retained instead of failing the grant.
  Future<Result<AuthTokens>> refresh(
    String refreshToken, {
    required String currentIdToken,
  }) => _tokenRequest({
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'client_id': config.clientId,
  }, fallbackIdToken: currentIdToken);

  /// 128 bits of CSPRNG entropy, base64url-encoded — login-CSRF protection.
  static String _generateState() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Extracts the `code` from the redirect; an IdP error response
  /// (`?error=...`) is mapped to a stable problem code. The redirect's `state`
  /// must equal the one sent with the request — any other value means the
  /// response was not initiated by this client and is rejected.
  Result<String> _extractCode(Uri redirect, {required String expectedState}) {
    final error = redirect.queryParameters['error'];
    if (error != null) {
      return Left(
        ProblemError(
          code: 'oidc.authorization_denied',
          detail: redirect.queryParameters['error_description'] ?? error,
        ),
      );
    }
    final state = redirect.queryParameters['state'];
    if (state != expectedState) {
      return const Left(
        ProblemError(
          code: 'oidc.state_mismatch',
          detail: 'authorization redirect state does not match the request',
        ),
      );
    }
    final code = redirect.queryParameters['code'];
    if (code == null || code.isEmpty) {
      return const Left(
        ProblemError(
          code: 'oidc.redirect_missing_code',
          detail: 'authorization redirect carried no code parameter',
        ),
      );
    }
    return Right(code);
  }

  /// Shared token-endpoint call (authorization-code and refresh grants).
  /// Never throws — every failure is a [ProblemError] value.
  ///
  /// Grant-aware `id_token` handling: required for authorization_code, MAY be
  /// absent from a refresh response (RFC 6749 §6 / OIDC Core §12) — in that
  /// case [fallbackIdToken] (the session's current ID token) is retained.
  Future<Result<AuthTokens>> _tokenRequest(
    Map<String, String> form, {
    String? fallbackIdToken,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        discovery.tokenEndpoint,
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
        ),
      );
      final body = response.data;
      if (body == null) {
        return const Left(ProblemError(code: 'oidc.token_response_empty'));
      }
      final accessToken = body['access_token'];
      final idToken = body['id_token'] ?? fallbackIdToken;
      if (accessToken is! String || idToken is! String || idToken.isEmpty) {
        return const Left(ProblemError(code: 'oidc.token_response_invalid'));
      }
      final refreshToken = body['refresh_token'];
      final expiresIn = body['expires_in'];
      return Right(
        AuthTokens(
          accessToken: accessToken,
          // Refresh grant responses may omit refresh_token (rotation optional
          // per RFC 6749 §6); keep the presented one in that case.
          refreshToken: refreshToken is String
              ? refreshToken
              : form['refresh_token'] ?? '',
          idToken: idToken,
          expiresAt: expiresIn is num
              ? DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt()))
              : null,
        ),
      );
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }
}
