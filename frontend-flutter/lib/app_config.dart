// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: muse-spark (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/foundation.dart' show kReleaseMode;

/// Runtime configuration for the Breakdown Flutter client.
///
/// Values are sourced from `--dart-define` build flags (never hardcoded,
/// per AGENTS.md §5). The two supported flavors are `dev` (localhost backend,
/// optional Logto IdP) and `prod` (deployed edge, Logto/Zitadel cloud).
enum Flavor { dev, prod }

/// Derives the flavor-effective OIDC redirect URI (issue #419, option 2b).
///
/// The dev flavor appends `-dev` to a CUSTOM scheme (`breakdown://` →
/// `breakdown-dev://`) so a co-installed prod app never competes for the
/// browser redirect — with distinct per-flavor application IDs, exactly one
/// installed app can ever receive the IdP redirect. This is the exact
/// textual mirror of the Gradle derivation (`devRedirectScheme` in
/// `android/app/build.gradle.kts`): scheme = text before `://` (else
/// before `:`), then `$scheme-dev` + the remainder. http/https schemes
/// (App-Links-style, host-based — not scheme-ambiguous) and scheme-less
/// values (neither `://` nor `:` — Gradle applies the same guard, so both
/// registration sites stay consistent; such a value can never route and
/// fails closed at the authorization UI) are returned unchanged; empty
/// stays empty (the startup guard owns that rejection). A base scheme
/// ending in the reserved `-dev` suffix is rejected at BUILD time by the
/// Gradle validation (it would make both flavors register the same
/// scheme), so the derivation here can append `-dev` unconditionally.
String deriveOidcRedirectUri(String uri, Flavor flavor) {
  if (flavor == Flavor.prod || uri.isEmpty) return uri;
  if (!uri.contains('://') && !uri.contains(':')) return uri;
  final scheme = _substringBefore(_substringBefore(uri, '://'), ':');
  final lower = scheme.toLowerCase();
  if (lower == 'http' || lower == 'https') return uri;
  return '$scheme-dev${uri.substring(scheme.length)}';
}

String _substringBefore(String s, String separator) {
  final index = s.indexOf(separator);
  return index == -1 ? s : s.substring(0, index);
}

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
  ///
  /// RAW `--dart-define` value (the same base URI `oidc-config.json`
  /// carries — `checkRedirectConsistency` compares the two raw values, and
  /// the per-flavor derivation is deterministic, so raw agreement implies
  /// derived agreement). Every consumer that talks to the IdP or matches
  /// incoming deep links MUST use [effectiveOidcRedirectUri], which scopes
  /// the scheme per flavor (dev: `breakdown://` → `breakdown-dev://`).
  final String oidcRedirectUri;

  /// The flavor-effective redirect URI: [oidcRedirectUri] run through
  /// [deriveOidcRedirectUri]. This is the URI the IdP must be registered
  /// with and the one the native deep-link manifest placeholder registers
  /// for this flavor.
  String get effectiveOidcRedirectUri =>
      deriveOidcRedirectUri(oidcRedirectUri, flavor);

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

  /// Copies this config with [apiBase] replaced (runtime backend-URI
  /// override application in `bootstrap()` — task 6.1; every other field
  /// stays exactly as `--dart-define` provided it).
  AppConfig copyWith({required String apiBase}) => AppConfig(
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
