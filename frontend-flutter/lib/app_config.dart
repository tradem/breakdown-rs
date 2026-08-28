// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

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
  });

  /// Reads configuration from the environment, defaulting the API base to the
  /// appropriate flavor endpoint when `API_BASE` is not supplied.
  factory AppConfig.fromEnvironment(Flavor flavor) {
    const apiBaseRaw = String.fromEnvironment('API_BASE');
    final apiBase = apiBaseRaw.isEmpty
        ? (flavor == Flavor.dev
              ? 'http://localhost:3000'
              : 'https://api.breakdown.rs')
        : apiBaseRaw;
    const oidcIss = String.fromEnvironment('OIDC_ISS');
    const devAuthSub = String.fromEnvironment('DEV_AUTH_SUB');

    return AppConfig(
      flavor: flavor,
      apiBase: apiBase,
      oidcIss: oidcIss,
      devAuthSub: devAuthSub,
    );
  }

  final Flavor flavor;
  final String apiBase;
  final String oidcIss;
  final String devAuthSub;

  bool get isDev => flavor == Flavor.dev;

  /// Dev-auth mode parity (scaffold Task 3.4): the dummy/permissive user is
  /// treated as authenticated only when `OIDC_ISS` is absent AND `DEV_AUTH_SUB`
  /// is set. This is intentionally impossible to satisfy in the `prod` flavor.
  bool get devAuthMode => isDev && oidcIss.isEmpty && devAuthSub.isNotEmpty;
}
