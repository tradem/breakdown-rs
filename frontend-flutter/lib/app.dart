// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'auth/auth_providers.dart';
import 'core/problem_error.dart';
import 'data/settings/api_base_override_store.dart';
import 'data/settings/api_base_validation.dart';
import 'design/spacing.dart';
import 'design/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/seasons/seasons_screen.dart';
import 'src/network/api_client.dart';

/// Root widget. Riverpod is the sole composition mechanism (AGENTS.md §1, D3);
/// widgets render and dispatch, they never branch on domain semantics.
///
/// The Material 3 theme pair comes from [AppThemes] with
/// `themeMode: ThemeMode.system` (spec `flutter-design-tokens`): a system
/// brightness change re-renders without an app restart. The content subtree
/// is the auth gate ([AuthGate], D1) — main-app screens are unreachable
/// without a resolved authenticated session because the subtree does not
/// exist.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Breakdown',
      theme: AppThemes.light(),
      darkTheme: AppThemes.dark(),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/// Root auth gate (D1, spec `flutter-auth-shell`). The ONLY place that
/// branches on auth state:
///
/// - `AsyncLoading` → [SplashView] (restore in flight — a pending restore
///   MUST NOT flash `LoginScreen`).
/// - `AsyncData(null)` → [LoginScreen] (signed out; the seasons subtree is
///   not built, so no main-app network call can happen).
/// - `AsyncData(session)` → [SeasonsScreen].
/// - `AsyncError` → [LoginScreen] with the failure surfaced. The error is
///   normalized to a stable-code [ProblemError] first: `AsyncError` is not
///   constrained to `ProblemError`, and the login error contract renders
///   localized copy keyed on `code` only — raw exception text or server
///   `detail` never reaches the screen.
/// - `AsyncLoading` carrying an error (Riverpod 3 auto-retries a failed
///   restore: while a retry is pending the state is loading WITH the
///   previous error seeded) → [LoginScreen] as well. Failing fast to the
///   login surface instead of flashing the splash through the backoff
///   window: a restore failure renders login, never splash.
///
/// Sign-out (failed or not) always lands here: a failed cleanup surfaces as
/// `AsyncError`, which still renders [LoginScreen], so main-app content is
/// never reachable and no stale projection is rendered after sign-out.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return switch (session) {
      AsyncError(:final error) => LoginScreen(
        restoreError: normalizeGateError(error),
      ),
      AsyncLoading(:final error) when error != null => LoginScreen(
        restoreError: normalizeGateError(error),
      ),
      AsyncLoading() => const SplashView(),
      AsyncData(:final value) => switch (value) {
        null => const LoginScreen(),
        _ => const SeasonsScreen(),
      },
    };
  }
}

/// Normalizes a gate failure to the login error contract: [ProblemError]
/// passes through; any other throw (e.g. a storage exception during
/// restore) maps to the stable generic `auth.restore_failed` code with
/// neutral copy. Exposed for tests (`@visibleForTesting`).
@visibleForTesting
ProblemError normalizeGateError(Object error) => error is ProblemError
    ? error
    : const ProblemError(code: 'auth.restore_failed');

/// Branded launch splash: design-token spacing and color-scheme roles only
/// (no hardcoded colors), with a [CircularProgressIndicator] for the
/// pending session restore.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.checkroom,
              key: const Key('splash-brand-icon'),
              size: 64,
              color: scheme.primary,
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(
              'Breakdown',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.space24),
            const CircularProgressIndicator(key: Key('splash-spinner')),
          ],
        ),
      ),
    );
  }
}

/// Fatal startup screen (D4 fail-closed): rendered THROUGH Flutter via
/// `runApp` — never a raw `throw` before `runApp` — so a bad build
/// configuration always surfaces as an honest error screen and no network
/// call is ever made with an unpinned or misconfigured client.
class FatalConfigErrorApp extends StatelessWidget {
  const FatalConfigErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breakdown — configuration error',
      home: Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_bad, size: 48, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'TLS configuration invalid',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The app cannot start safely: $error\n'
                  'No network requests were made.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Composition root. Validates the build configuration fail-closed, builds
/// the pinned-CA HTTP transports, and overrides the composition providers.
///
/// Startup guards (all abort with the fatal screen BEFORE any HTTP client or
/// network call exists):
/// - D1: `DEV_IDP_INSECURE=1` under any non-dev flavor or in a release build.
/// - Task 5.1: `DEV_AUTH_SUB` set in the `prod` flavor (dev-auth parity is
///   structurally unreachable in prod; this makes a misconfigured build loud).
/// - D4: the pinned-CA source is missing/empty/not valid PEM → "TLS
///   configuration invalid" screen, no `HttpClient` constructed.
/// - OIDC: a non-dev-auth build without `OIDC_ISS`/`OIDC_CLIENT_ID`/
///   `OIDC_REDIRECT_URI` cannot authenticate (backend ADR-018 fails startup
///   without real IdP config or `DEV_AUTH_SUB` — the client mirrors that
///   fail-closed posture).
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await resolveAppConfig(flavor);

  final configError = validateStartupConfig(config);
  if (configError != null) {
    runApp(FatalConfigErrorApp(error: configError));
    return;
  }

  // The native deep-link registration was derived from oidc-config.json
  // at Gradle time; prove the compiled dart-define agrees before any
  // client exists — a drifted define would hang the sign-in on device.
  final redirectError = await checkRedirectConsistency(config);
  if (redirectError != null) {
    runApp(FatalConfigErrorApp(error: redirectError));
    return;
  }

  Object? tlsError;
  Dio? apiDio;
  Dio? idpDio;
  SecurityContext? pinnedContext;
  try {
    // The pinned context is loaded once and shared: `buildApiClient` uses
    // it for the bootstrap Dio, and `apiDioProvider` reuses it across
    // runtime base-URL rebuilds (task 6.3).
    pinnedContext = await loadPinnedSecurityContext(config);
    apiDio = await buildApiClient(config);
    idpDio = await buildIdpDio(config);
  } on TlsConfigError catch (e) {
    tlsError = e;
  }
  if (tlsError != null ||
      apiDio == null ||
      idpDio == null ||
      pinnedContext == null) {
    runApp(
      FatalConfigErrorApp(error: tlsError ?? 'HTTP client construction failed'),
    );
    return;
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        dioProvider.overrideWithValue(apiDio),
        idpDioProvider.overrideWith((ref) => Future.value(idpDio)),
        pinnedSecurityContextProvider.overrideWithValue(pinnedContext),
      ],
      child: const App(),
    ),
  );
}

/// Resolves the effective runtime configuration: [AppConfig.fromEnvironment]
/// (compile-time `--dart-define` values) with the persisted backend-URI
/// override applied on top (task 6.1). No request is ever constructed before
/// this returns, so no request can target the compile-time base when an
/// override is stored. Exposed for tests (`@visibleForTesting`); production
/// calls it from [bootstrap].
@visibleForTesting
Future<AppConfig> resolveAppConfig(Flavor flavor) async {
  final base = AppConfig.fromEnvironment(flavor);
  return applyApiBaseOverride(base);
}

/// Applies the persisted `api_base_override` (if any) to [config].
///
/// Flavor-guarded (spec `flutter-app-dialogs`): the override applies ONLY
/// in `dev`. In `prod` a stored override — e.g. left over from a dev
/// install over the same application ID (Android ships one ID, no product
/// flavors) — is ignored AND cleared on boot; the compile-time HTTPS base
/// is always used. An invalid stored value is ignored (the dialog validates
/// on save; this is the defensive second check). A store read failure falls
/// back to the compile-time base (secure-storage breakage already surfaces
/// via session restore at the gate).
@visibleForTesting
Future<AppConfig> applyApiBaseOverride(AppConfig config) async {
  final store = ApiBaseOverrideStore.secure();
  final override = (await store.read()).getRight().toNullable();
  if (override == null || override.isEmpty) return config;
  if (config.flavor != Flavor.dev) {
    // Best-effort cleanup: a failed clear only leaves a stale override
    // that the next boot ignores (and retries clearing) the same way.
    (await store.clear()).fold((_) {}, (_) {});
    return config;
  }
  return validateApiBase(
    override,
    isDev: true,
  ).match((_) => config, (base) => config.copyWith(apiBase: base));
}

/// Proves the compiled `OIDC_REDIRECT_URI` dart-define matches the bundled
/// `oidc-config.json` that Gradle used for the native deep-link
/// registration (task 3.3 follow-up: an explicit `--dart-define` bypasses
/// both the file and the environment, which neither side can otherwise see).
/// Fail-closed: any mismatch aborts startup with an actionable message
/// instead of hanging the sign-in on device. Skipped in dev-auth mode (no
/// OIDC) and when no redirect is configured at all (already rejected by
/// [validateStartupConfig] unless dev-auth applies). Exposed for tests.
@visibleForTesting
Future<String?> checkRedirectConsistency(
  AppConfig config, {
  // Asset-loading seam: production reads the bundled file; tests inject
  // canned JSON (unit-test bundles do not carry app assets).
  Future<String> Function(String key)? loadAsset,
}) async {
  if (config.devAuthMode || config.oidcRedirectUri.isEmpty) return null;
  String? fileUri;
  try {
    final load = loadAsset ?? rootBundle.loadString;
    final decoded = jsonDecode(await load('oidc-config.json'));
    if (decoded is Map<String, dynamic>) {
      final value = decoded['OIDC_REDIRECT_URI'];
      if (value is String) fileUri = value;
    }
  } catch (_) {
    return 'OIDC redirect configuration unreadable: '
        'oidc-config.json missing from the bundle';
  }
  return redirectMismatchError(
    fileUri: fileUri,
    defineUri: config.oidcRedirectUri,
  );
}

/// Pure comparison behind [checkRedirectConsistency] (Tier-1 testable):
/// returns an error description on mismatch, `null` when file and define
/// agree.
@visibleForTesting
String? redirectMismatchError({
  required String? fileUri,
  required String defineUri,
}) {
  if (fileUri == null || fileUri.isEmpty) {
    return 'OIDC redirect configuration unreadable: '
        'oidc-config.json carries no OIDC_REDIRECT_URI';
  }
  if (fileUri != defineUri) {
    return 'OIDC_REDIRECT_URI dart-define ($defineUri) does not match '
        'oidc-config.json ($fileUri) used for the native deep-link '
        'registration. Set the URI in oidc-config.json and pass it via '
        '--dart-define-from-file instead of --dart-define.';
  }
  return null;
}

/// Returns a human-readable reason when the build configuration violates a
/// startup guard, or `null` when the configuration is valid. Exposed for
/// tests (`@visibleForTesting`); production calls it from [bootstrap].
@visibleForTesting
String? validateStartupConfig(AppConfig config) {
  // D1: the dev IdP HTTP exception must be impossible outside a dev,
  // non-release build. This is an explicit guard, not a Dart assert —
  // asserts vanish under `--release`.
  if (config.devIdpInsecure == '1') {
    if (config.flavor != Flavor.dev) {
      return 'DEV_IDP_INSECURE=1 is only allowed in the dev flavor';
    }
    if (kReleaseMode) {
      return 'DEV_IDP_INSECURE=1 cannot be set in a release build';
    }
  }
  // Task 5.1: dev-auth parity is dev-flavor-only; a prod build carrying
  // DEV_AUTH_SUB is a misconfiguration, not a silent permissive session.
  if (config.flavor == Flavor.prod && config.devAuthSub.isNotEmpty) {
    return 'DEV_AUTH_SUB must never be set in the prod flavor';
  }
  // Fail-closed auth posture (ADR-018 parity): a build that is not in
  // dev-auth mode needs real IdP configuration to authenticate at all.
  if (!config.devAuthMode &&
      (config.oidcIss.isEmpty ||
          config.oidcClientId.isEmpty ||
          config.oidcRedirectUri.isEmpty)) {
    return 'OIDC configuration invalid: OIDC_ISS, OIDC_CLIENT_ID and '
        'OIDC_REDIRECT_URI are required unless the dev-auth mode '
        '(DEV_AUTH_SUB, dev flavor only) is used';
  }
  return null;
}
