// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_config.dart';
import '../core/problem_error.dart';
import '../core/result.dart';
import 'oidc_client.dart';
import 'oidc_discovery.dart';
import 'platform_authorization_ui.dart';
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

/// The platform browser/deep-link leg of the authorization flow.
///
/// Resolves to [PlatformAuthorizationUi] (Custom Tabs + `app_links`
/// redirect capture, spec `flutter-auth-shell`) whenever the build carries
/// a routable `OIDC_REDIRECT_URI`; otherwise the fail-closed
/// [NotConfiguredAuthorizationUi] — without a redirect the platform leg
/// could never return, so no authorization request may start. Tests inject
/// fakes via overrides.
@Riverpod(keepAlive: true)
AuthorizationUi authorizationUi(Ref ref) {
  final redirect = Uri.tryParse(ref.watch(appConfigProvider).oidcRedirectUri);
  if (redirect == null || redirect.scheme.isEmpty) {
    return const NotConfiguredAuthorizationUi();
  }
  return PlatformAuthorizationUi(redirectUri: redirect);
}

/// Fail-closed stand-in for the not-yet-wired platform browser/deep-link leg:
/// sign-in surfaces a clear error instead of crashing with
/// `UnimplementedError`. Never relaxes anything — no authorization request is
/// started, and the API/IdP transports are unaffected.
class NotConfiguredAuthorizationUi implements AuthorizationUi {
  const NotConfiguredAuthorizationUi();

  @override
  Future<Result<Uri>> launch(Uri authorizationUrl) async => const Left(
    ProblemError(
      code: 'oidc.authorization_ui_not_configured',
      detail: 'platform browser wiring is not installed in this build',
    ),
  );
}

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
///   parity, Task 5.1): boots SIGNED OUT at the login gate (spec
///   `flutter-auth-shell` — the gate's dev-auth notice + Continue action
///   resolves the permissive [AuthSession] explicitly via [signIn]).
///   Structurally unreachable in `prod` (`AppConfig.devAuthMode` requires
///   the dev flavor) and the composition root aborts startup if prod ever
///   carries the flag.
/// - Otherwise: the session is restored from secure storage; `null` means
///   signed out. Use [signIn]/[signOut] to mutate.
@Riverpod(keepAlive: true)
class AuthSessionController extends _$AuthSessionController {
  /// Handshake for in-flight `build()` passes (initial restore or a
  /// retry): external mutations ([signIn]/[signOut]) must wait for it —
  /// assigning `state` while a build is pending is clobbered when that
  /// build completes. Set synchronously as the first step of every build.
  Completer<void>? _settleGate;

  /// Waits until no build is in flight. Loops (instead of awaiting once)
  /// because a retry may start a fresh build pass while the previous one
  /// completes. Terminates: builds always settle (success or `AsyncError`)
  /// and retries are bounded (Riverpod default policy).
  Future<void> _settleInitialization() async {
    while (state is AsyncLoading) {
      final gate = _settleGate;
      if (gate == null) {
        await Future<void>.delayed(Duration.zero);
      } else {
        await gate.future;
      }
    }
  }

  @override
  Future<AuthSession?> build() async {
    final gate = Completer<void>();
    _settleGate = gate;
    try {
      return await _restore();
    } finally {
      _settleGate = null;
      gate.complete();
    }
  }

  /// Session restore: permissive dev-auth session, else secure-storage
  /// read (`null` = signed out; `Err` → throw → `AsyncError`, never
  /// swallowed, AGENTS.md §5).
  Future<AuthSession?> _restore() async {
    final config = ref.watch(appConfigProvider);
    if (config.devAuthMode) {
      // Explicit gate: even the permissive session requires the Continue
      // action (see [signIn]) — the app always boots at `LoginScreen`.
      return null;
    }
    final res = await ref.watch(tokenStoreProvider).read();
    return res.match(
      (e) => throw e,
      (tokens) => tokens == null
          ? null
          : AuthSession(
              sub: subFromIdToken(tokens.idToken) ?? '',
              tokens: tokens,
            ),
    );
  }

  /// Runs the PKCE authorization flow, persists the tokens, and switches to
  /// the authenticated session. In dev-auth mode it resolves the permissive
  /// session explicitly (no network, no tokens). An authorization/refresh
  /// failure is surfaced as `AsyncError` (never swallowed, AGENTS.md §5).
  Future<void> signIn() async {
    // Settle-before-mutate (see [_settleInitialization]): the gate only
    // offers sign-in after settle, but a retry window can still be pending
    // (see `AuthGate`), and callers may dispatch immediately after
    // container creation. A failed restore must not block signing in —
    // the gate surfaces it.
    await _settleInitialization();
    final config = ref.watch(appConfigProvider);
    if (config.devAuthMode) {
      // Dev-auth Continue (spec `flutter-auth-shell`): the login screen's
      // Continue action resolves the permissive session explicitly so the
      // root gate recomposes to the main app (no network, no tokens).
      state = AsyncData(AuthSession(sub: config.devAuthSub));
      return;
    }

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

  /// Signs out: clears tokens, then recomposes the root to `LoginScreen`.
  /// Cache emptying and provider invalidation run in `SessionReset`
  /// (features-side — this file cannot import `features/` providers
  /// without an import cycle).
  ///
  /// Fail-closed: a token-store `Err` leaves the state as `AsyncError` —
  /// the root leaves the authenticated gate anyway (no stale projection is
  /// ever rendered) and the failure surfaces with a retry affordance.
  ///
  /// Never throws: failures are `AsyncError` state, so menu callers need no
  /// error handling (the gate renders the error surface).
  Future<void> signOut() async {
    // Same settle-before-mutate race as [signIn] (see above).
    await _settleInitialization();
    final config = ref.watch(appConfigProvider);
    if (!config.devAuthMode) {
      final cleared = await ref.read(tokenStoreProvider).clear();
      final clearError = cleared.getLeft().toNullable();
      if (clearError != null) {
        // Tokens remain on disk: report failure and stop — `SessionReset`
        // still empties the cache and invalidates, and a retry re-attempts
        // the token wipe first (token deletion is idempotent).
        state = AsyncError(clearError, StackTrace.current);
        return;
      }
    }
    state = const AsyncData(null);
  }

  /// Marks the session as failed (used by session-reset flows whose
  /// post-token step fails — e.g. the Drift cache clear in `SessionReset`).
  /// Fail-closed like [signOut]: the gate leaves the authenticated subtree.
  void failSession(ProblemError error) {
    state = AsyncError(error, StackTrace.current);
  }
}
