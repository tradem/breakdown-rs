// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/foundation.dart' show kReleaseMode;

/// Runtime configuration for the Breakdown Flutter client.
///
/// Values are sourced from `--dart-define` build flags (never hardcoded,
/// per AGENTS.md §5). The two supported flavors are `dev` (localhost backend,
/// optional Logto IdP) and `prod` (deployed edge, Logto/Zitadel cloud).
enum Flavor { dev, prod }

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBase,
    required this.oidcIss,
    required this.devAuthSub,
    required this.oidcAudience,
    required this.oidcClientId,
    required this.oidcRedirectUri,
    required this.devIdpInsecure,
    required this.appVersion,
    this.defaultSeriesId = '',
  });

  /// Reads configuration from the environment, defaulting the API base to the
  /// appropriate flavor endpoint when `API_BASE` is not supplied.
  ///
  /// The dev default uses `10.0.2.2` (Android emulator → host loopback) rather
  /// than `localhost` (which targets the device itself). Physical devices and
  /// other targets should supply an explicit `API_BASE` override.
  factory AppConfig.fromEnvironment(Flavor flavor) {
    const apiBaseRaw = String.fromEnvironment('API_BASE');
    final apiBase = apiBaseRaw.isEmpty
        ? (flavor == Flavor.dev
              ? 'http://10.0.2.2:3000'
              : 'https://api.breakdown.rs')
        : apiBaseRaw;
    const oidcIss = String.fromEnvironment('OIDC_ISS');
    const devAuthSub = String.fromEnvironment('DEV_AUTH_SUB');
    const oidcAudience = String.fromEnvironment('OIDC_AUDIENCE');
    const oidcClientId = String.fromEnvironment('OIDC_CLIENT_ID');
    const oidcRedirectUri = String.fromEnvironment('OIDC_REDIRECT_URI');
    // D1 exception flag — read ONLY where a dev-flavor guard allows it; the
    // composition root aborts startup when it is set under any non-dev flavor
    // or a release build (see bootstrap()).
    const devIdpInsecure = String.fromEnvironment('DEV_IDP_INSECURE');
    // Application version for the About/Info dialog (spec flutter-app-dialogs,
    // ADR-033 D5): CI injects `--dart-define=APP_VERSION=<X.Y.Z+N>`; local
    // builds without the define fall back to 'unknown' (the spec'd fallback).
    // Never hardcoded — the single source of truth is pubspec.yaml.
    const appVersionRaw = String.fromEnvironment('APP_VERSION');
    final appVersion = appVersionRaw.isEmpty ? 'unknown' : appVersionRaw;
    // Optional pre-fill for season-creating forms. Env-sourced, never
    // hardcoded (AGENTS.md §5); the field stays editable when absent.
    const defaultSeriesId = String.fromEnvironment('DEFAULT_SERIES_ID');

    return AppConfig(
      flavor: flavor,
      apiBase: apiBase,
      oidcIss: oidcIss,
      devAuthSub: devAuthSub,
      oidcAudience: oidcAudience,
      oidcClientId: oidcClientId,
      oidcRedirectUri: oidcRedirectUri,
      devIdpInsecure: devIdpInsecure,
      appVersion: appVersion,
      defaultSeriesId: defaultSeriesId,
    );
  }

  final Flavor flavor;
  final String apiBase;
  final String oidcIss;
  final String devAuthSub;

  /// Requested token audience — mirrors the backend's `OIDC_AUDIENCE` (ADR-018);
  /// the backend independently validates the token's `aud` claim.
  final String oidcAudience;

  /// Public PKCE client id (no client secret on a public native client).
  final String oidcClientId;

  /// Deep-link redirect URI the IdP redirects back to after authorization.
  final String oidcRedirectUri;

  /// Raw `DEV_IDP_INSECURE` dart-define. NEVER consult this directly outside
  /// a dev-flavor, non-release guard; see [devIdpHttpAllowed] and the
  /// startup checks in `bootstrap()` (D1 — dev-flavor-only documented
  /// exception, impossible in prod/release).
  final String devIdpInsecure;

  /// Display version for the About/Info dialog (spec flutter-app-dialogs,
  /// ADR-033 D5): the CI-injected `APP_VERSION` define, or `'unknown'` for
  /// local builds. Native `version`/`buildNumber` (pubspec `X.Y.Z+N`, incl.
  /// CI `--build-name`/`--build-number` overrides) are readable via
  /// `package_info_plus` and SHOULD equal this value in release builds
  /// (enforced by the `version-drift` CI job).
  final String appVersion;

  /// `DEFAULT_SERIES_ID` dart-define (may be empty). Used only as a form
  /// pre-fill; the authoritative `series_id` of a season always comes from
  /// the server's projection, never from this value.
  final String defaultSeriesId;

  bool get isDev => flavor == Flavor.dev;

  /// Dev-auth mode parity (scaffold Task 3.4): the dummy/permissive user is
  /// treated as authenticated only when `OIDC_ISS` is absent AND `DEV_AUTH_SUB`
  /// is set — the exact backend predicate (ADR-018 D6). This is intentionally
  /// impossible to satisfy in the `prod` flavor.
  bool get devAuthMode => isDev && oidcIss.isEmpty && devAuthSub.isNotEmpty;

  /// Whether the documented dev IdP HTTP port-forward exception (D1) is active:
  /// dev flavor only, non-release only, and only when the flag is explicitly
  /// set. Every non-dev flavor and every release build rejects the flag at
  /// startup (bootstrap()), so this can never relax pinning in a prod
  /// artifact. Even when true, only the IdP host's transport is relaxed — the
  /// API host remains pinned.
  bool get devIdpHttpAllowed => isDev && !kReleaseMode && devIdpInsecure == '1';
}
