// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// OAuth tokens for one authenticated session (ADR-010 OIDC contract).
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    this.expiresAt,
  });

  /// Bearer token sent as `Authorization: Bearer <access>` to the API.
  final String accessToken;

  /// Rotate-on-use refresh token (online-first refresh, no offline queue —
  /// `flutter-offline-scope`).
  final String refreshToken;

  /// OIDC ID token (identity claims; the backend re-validates independently).
  final String idToken;

  /// When [accessToken] expires (IdP clock); used to refresh proactively.
  final DateTime? expiresAt;

  /// Whether the access token is at or past its proactive-refresh deadline.
  bool get isExpired {
    final at = expiresAt;
    return at != null && !at.isAfter(DateTime.now().toUtc());
  }
}

/// Abstract token persistence (Task 2.1).
///
/// Tokens live ONLY in secure storage (`flutter_secure_storage` — Android
/// Keystore); plaintext preferences are forbidden (AGENTS.md §5). The
/// interface exists so tests can inject an in-memory fake and so the storage
/// backend stays swappable.
abstract interface class TokenStore {
  /// Persists a full token set, replacing any previous session.
  Future<Result<void>> save(AuthTokens tokens);

  /// Reads the current token set, or `null` when signed out.
  Future<Result<AuthTokens?>> read();

  /// Clears all stored tokens (sign-out / token-nuke).
  Future<Result<void>> clear();
}

/// [TokenStore] backed by `flutter_secure_storage`.
///
/// Keys are fixed constants; values are opaque strings written through the
/// platform secure enclave. No `SharedPreferences`/file fallback exists by
/// design (Task 2.2 — no plaintext anywhere).
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kAccess = 'breakdown.oidc.access_token';
  static const _kRefresh = 'breakdown.oidc.refresh_token';
  static const _kIdJwt = 'breakdown.oidc.id_token';
  static const _kExpiresAt = 'breakdown.oidc.expires_at';

  final FlutterSecureStorage _storage;

  @override
  Future<Result<void>> save(AuthTokens tokens) async {
    try {
      await _storage.write(key: _kAccess, value: tokens.accessToken);
      await _storage.write(key: _kRefresh, value: tokens.refreshToken);
      await _storage.write(key: _kIdJwt, value: tokens.idToken);
      final at = tokens.expiresAt;
      await _storage.write(key: _kExpiresAt, value: at?.toIso8601String());
      return const Right(null);
    } catch (e) {
      // A failed save must never leave a MIXED session (e.g. new access token
      // with the previous user's refresh/ID token — the UI would identify one
      // user while API calls authenticate as another). Wipe every session
      // field before propagating the error; read() then reports signed-out.
      try {
        await _storage.delete(key: _kAccess);
        await _storage.delete(key: _kRefresh);
        await _storage.delete(key: _kIdJwt);
        await _storage.delete(key: _kExpiresAt);
      } catch (_) {
        // The wipe itself failing cannot be reported more loudly than the
        // original error; the caller already gets a failed save.
      }
      return Left(
        ProblemError(code: 'auth.token_store_write_failed', detail: '$e'),
      );
    }
  }

  @override
  Future<Result<AuthTokens?>> read() async {
    try {
      final access = await _storage.read(key: _kAccess);
      if (access == null) return const Right(null);
      final refresh = await _storage.read(key: _kRefresh);
      final idToken = await _storage.read(key: _kIdJwt);
      final expiresRaw = await _storage.read(key: _kExpiresAt);
      if (refresh == null || idToken == null) {
        // A partially-persisted session is corrupt: treat as signed out and
        // clear the remainder rather than returning unusable tokens. A failed
        // cleanup is surfaced — secure storage itself is broken.
        final cleanup = await clear();
        return cleanup.fold<Result<AuthTokens?>>(
          (e) => Left(e),
          (_) => const Right(null),
        );
      }
      return Right(
        AuthTokens(
          accessToken: access,
          refreshToken: refresh,
          idToken: idToken,
          expiresAt: expiresRaw == null ? null : DateTime.tryParse(expiresRaw),
        ),
      );
    } catch (e) {
      return Left(
        ProblemError(code: 'auth.token_store_read_failed', detail: '$e'),
      );
    }
  }

  @override
  Future<Result<void>> clear() async {
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
      await _storage.delete(key: _kIdJwt);
      await _storage.delete(key: _kExpiresAt);
      return const Right(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'auth.token_store_clear_failed', detail: '$e'),
      );
    }
  }
}

/// Extracts the `sub` claim from an ID token's payload for display only.
///
/// This is NOT verification — the backend independently validates the token
/// signature/`iss`/`aud` against the IdP JWKS (ADR-018). The client never
/// makes authorization decisions from ID-token claims; membership comes from
/// `currentMembershipProvider` (server-computed).
String? subFromIdToken(String idToken) {
  final parts = idToken.split('.');
  if (parts.length != 3) return null;
  final normalized = base64Url.normalize(parts[1]);
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    final sub = payload is Map<String, dynamic> ? payload['sub'] : null;
    return sub is String ? sub : null;
  } on FormatException {
    return null;
  }
}
