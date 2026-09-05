// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:dio/dio.dart';

import '../../auth/token_store.dart';

/// Attaches the session bearer token to API traffic (spec
/// `flutter-app-dialogs`, task 6.x cleartext rule).
///
/// Attach-only (no refresh logic — token lifecycle is a documented gap,
/// design.md §7.2; a 401 surfaces through the standard keyed-on-`code`
/// error path):
/// - the `Authorization: Bearer` header is attached ONLY when the request
///   URI uses `https` (the pinned-CA transport);
/// - on cleartext `http` (dev emulator/loopback overrides only — validation
///   rejects anything else) the credential is ALWAYS withheld (CWE-319: no
///   session credential is ever transmitted in the clear to an arbitrary
///   host);
/// - a token-store read failure proceeds WITHOUT a token (session restore
///   would already have failed before any authenticated screen exists).
///   Never throws.
class AuthTokenInterceptor extends Interceptor {
  const AuthTokenInterceptor(this._tokenStore);

  final TokenStore _tokenStore;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.uri.scheme == 'https') {
      String? accessToken;
      try {
        accessToken = (await _tokenStore.read())
            .getRight()
            .toNullable()
            ?.accessToken;
      } catch (_) {
        accessToken = null;
      }
      if (accessToken != null && accessToken.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
    }
    handler.next(options);
  }
}
