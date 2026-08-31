// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'auth/auth_providers.dart';
import 'src/network/api_client.dart';

/// Root widget. Riverpod is the sole composition mechanism (AGENTS.md §1, D3);
/// widgets render and dispatch, they never branch on domain semantics.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breakdown',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Breakdown')),
        body: const Center(child: Text('Breakdown')),
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
  final config = AppConfig.fromEnvironment(flavor);

  final configError = validateStartupConfig(config);
  if (configError != null) {
    runApp(FatalConfigErrorApp(error: configError));
    return;
  }

  Object? tlsError;
  Dio? apiDio;
  Dio? idpDio;
  try {
    apiDio = await buildApiClient(config);
    idpDio = await buildIdpDio(config);
  } on TlsConfigError catch (e) {
    tlsError = e;
  }
  if (tlsError != null || apiDio == null || idpDio == null) {
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
      ],
      child: const App(),
    ),
  );
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
