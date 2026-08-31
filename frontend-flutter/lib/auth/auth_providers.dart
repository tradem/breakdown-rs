// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_config.dart';
import '../core/problem_error.dart';
import '../core/result.dart';
import 'oidc_client.dart';
import 'oidc_discovery.dart';
import 'token_store.dart';

part 'auth_providers.g.dart';

/// The resolved per-flavor runtime configuration. Overridden at the
/// composition root (`bootstrap()` in `app.dart`) with the value built from
/// `--dart-define`; reading it before the override is a programming error.
@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) => throw UnimplementedError(
  'appConfigProvider must be overridden at bootstrap',
);

/// The pinned-CA [Dio] for API traffic. Overridden at the composition root
/// with the client built by `buildApiClient` (fail-closed TLS, D4).
@Riverpod(keepAlive: true)
Dio dio(Ref ref) =>
    throw UnimplementedError('dioProvider must be overridden at bootstrap');

/// The [Dio] used for IdP (discovery/token) traffic: pinned by default,
/// plain-verifying only under the dev-flavor D1 exception.
@Riverpod(keepAlive: true)
Future<Dio> idpDio(Ref ref) =>
    throw UnimplementedError('idpDioProvider must be overridden at bootstrap');

/// Secure token persistence (`flutter_secure_storage` — never plaintext,
/// Task 2.1).
@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => SecureTokenStore();

/// OIDC client parameters from the environment (public PKCE client — no
/// secrets in the client tree, AGENTS.md §5).
@Riverpod(keepAlive: true)
OidcClientConfig oidcClientConfig(Ref ref) {
  final config = ref.watch(appConfigProvider);
  return OidcClientConfig(
    clientId: config.oidcClientId,
    redirectUri: config.oidcRedirectUri,
    audience: config.oidcAudience.isEmpty ? null : config.oidcAudience,
  );
}

/// Discovers the IdP's OIDC metadata over the IdP transport and validates the
/// issuer identity (Task 1.2, ADR-010/018). Fails closed as `AsyncError` when
/// discovery or the issuer check fails.
@Riverpod(keepAlive: true)
Future<Result<OidcClient>> oidcClient(Ref ref) async {
  final config = ref.watch(appConfigProvider);
  final dio = await ref.watch(idpDioProvider.future);
  final discovery = await discoverOidc(dio, config.oidcIss);
  return discovery.match(
    Left.new,
    (doc) => Right(
      OidcClient(
        dio: dio,
        discovery: doc,
        config: ref.watch(oidcClientConfigProvider),
        authorizationUi: ref.watch(authorizationUiProvider),
      ),
    ),
  );
}

/// The platform browser/deep-link leg of the authorization flow. Overridden
/// at the composition root once the native Custom-Tabs wiring lands; tests
/// inject fakes.
@Riverpod(keepAlive: true)
AuthorizationUi authorizationUi(Ref ref) => throw UnimplementedError(
  'authorizationUiProvider must be overridden (platform browser wiring)',
);

/// One authenticated session. [tokens] is `null` in dev-auth mode (the
/// backend skips verification for `DEV_AUTH_SUB`, so there are no real
/// tokens to hold — ADR-018 D6).
class AuthSession {
  const AuthSession({required this.sub, this.tokens});

  /// The authenticated subject. In dev-auth mode this is `DEV_AUTH_SUB`.
  final String sub;

  final AuthTokens? tokens;

  /// True when this is the permissive dev-auth session (no real tokens).
  bool get isDevAuth => tokens == null;
}

/// The current auth session.
///
/// - Dev-auth mode (`DEV_AUTH_SUB`, no `OIDC_ISS` — backend ADR-018 D6
///   parity, Task 5.1): a permissive [AuthSession] with `DEV_AUTH_SUB` as
///   subject, no network, no tokens. Structurally unreachable in `prod`
///   (`AppConfig.devAuthMode` requires the dev flavor) and the composition
///   root aborts startup if prod ever carries the flag.
/// - Otherwise: the session is restored from secure storage; `null` means
///   signed out. Use [signIn]/[signOut] to mutate.
@Riverpod(keepAlive: true)
class AuthSessionController extends _$AuthSessionController {
  @override
  Future<AuthSession?> build() async {
    final config = ref.watch(appConfigProvider);
    if (config.devAuthMode) {
      return AuthSession(sub: config.devAuthSub);
    }
    final res = await ref.watch(tokenStoreProvider).read();
    return res.match(
      (e) => throw e, // Err → AsyncError (never swallowed, AGENTS.md §5)
      (tokens) => tokens == null
          ? null
          : AuthSession(
              sub: subFromIdToken(tokens.idToken) ?? '',
              tokens: tokens,
            ),
    );
  }

  /// Runs the PKCE authorization flow, persists the tokens, and switches to
  /// the authenticated session. No-op (returns current state) in dev-auth
  /// mode — already authenticated. An authorization/refresh failure is
  /// surfaced as `AsyncError` (never swallowed, AGENTS.md §5).
  Future<void> signIn() async {
    final config = ref.watch(appConfigProvider);
    if (config.devAuthMode) return;

    final clientResult = await ref.read(oidcClientProvider.future);
    final tokensResult = await clientResult.match(
      (e) async => Left<ProblemError, AuthTokens>(e),
      (client) => client.authorize(),
    );
    final saved = await tokensResult.match(
      (e) async => Left<ProblemError, AuthTokens>(e),
      (tokens) async {
        final res = await ref.read(tokenStoreProvider).save(tokens);
        return res.map((_) => tokens);
      },
    );
    if (saved.isLeft()) {
      throw saved.getLeft().toNullable()!; // Err → AsyncError translation
    }
    final tokens = saved.getRight().toNullable()!;
    state = AsyncData(
      AuthSession(sub: subFromIdToken(tokens.idToken) ?? '', tokens: tokens),
    );
  }

  /// Clears tokens and returns to signed-out.
  Future<void> signOut() async {
    final config = ref.watch(appConfigProvider);
    if (config.devAuthMode) return;
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }
}
