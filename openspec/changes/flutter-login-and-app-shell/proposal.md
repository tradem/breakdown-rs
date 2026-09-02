<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Login & App Shell — Phase 1a

## Why
The app currently boots straight into `SeasonsScreen` (`lib/app.dart`).
There is no login UI (the OIDC client exists in `lib/auth/` but its
platform browser leg is the fail-closed `NotConfiguredAuthorizationUi`
stand-in), no sign-out affordance, no light/dark theming beyond a single
hardcoded light `ThemeData`, and no place for the legal and configuration
surfaces a store-distributable app needs: an info dialog (license, AI
usage notice, version number) and a settings dialog (runtime backend URI).

The feature roadmap places login/OIDC + membership UI in Phase 1. This
change lands it, together with the app-shell chrome (identity, sign-out,
About, Settings) those dialogs hang from and the minimal design tokens
(`lib/design/`) every subsequent screen renders against.

## What changes
- `lib/auth/`: wire a real platform `AuthorizationUi` (Android Custom Tabs
  via `url_launcher`, deep-link redirect capture via `app_links`) so OIDC
  sign-in completes end-to-end on device; keep the injected seam for tests.
- `lib/features/auth/`: `LoginScreen` — ConsumerWidget, sign-in dispatch,
  localized error surface keyed on problem `code`, dev-auth-mode notice.
- `lib/app.dart`: auth gate — the root switches on
  `authSessionControllerProvider` (loading → splash, unauthenticated →
  `LoginScreen`, authenticated → the app). Sign-out returns to
  `LoginScreen` and invalidates session-scoped state.
- `lib/design/`: theme tokens + `AppThemes.light` / `AppThemes.dark`
  (`ColorScheme.fromSeed`, teal seed as today, no hardcoded widget-level
  colors/typography/spacing); `App` renders `theme` + `darkTheme` with
  `themeMode` following system brightness.
- `lib/features/app_info/`: About/Info dialog (version from
  `--dart-define=APP_VERSION`, AGPL-3.0 license + source link, AI usage
  notice) and Settings dialog with the runtime backend-URI override
  (dev flavor only; see D5) exposing `AppBar` menu entries on the shell.
- Runtime API-base override: `runtimeApiBaseProvider` (Notifier over
  `flutter_secure_storage`), rebuildable pinned-CA Dio, Drift cache reset
  on base change; applied at bootstrap before any network call.
- Tests: unit (override persistence, URI validation, capability-free
  login-state machine), widget + golden (light AND dark), integration_test
  smoke (login gate on a device build in dev-auth mode).

## Capabilities
- `flutter-auth-shell` (new): session gating, login screen, OIDC platform
  wiring, identity/sign-out.
- `flutter-design-tokens` (new): light/dark M3 theming + token discipline.
- `flutter-app-dialogs` (new): About/info dialog, settings dialog with the
  dev backend-URI override.

## Dependencies
- **Depends on (all landed):** `wire-flutter-oidc-auth` (session
  controller, token store, OIDC client, `NotConfiguredAuthorizationUi`
  seam), `wire-openapi-dart-client` (generated client), `add-drift-read-cache`
  (cache database reset seam reuses it), `scaffold-flutter-project`,
  `first-screen-seasons` (shell hosts the existing screen).
- **New package dependencies:** `url_launcher`, `app_links` — FOSS,
  store-compliant; orthogonal to state management/routing (no BLoC/GetIt/
  go_router, unchanged). `flutter_secure_storage` and `dio` already
  present.

## Non-goals
- No proactive OIDC token refresh / silent re-auth (documented gap, see
  `design.md` §7 — 401s surface as errors on the affected screens).
- No membership/role display beyond the authenticated identity (season
  membership UI lands with `flutter-hierarchy-navigation`).
- No declarative routing (`lib/routing/`, `MaterialApp.router`) — routing
  decisions require their own OpenSpec change; the gate stays a single-tree
  switch (see `design.md` §4).
- No exhaustive design-system component library — only the tokens and
  components this change's surfaces need.
- No other screens (Phase 1b/2/3 follow-up changes).

## Design Decisions
- **D1 — Auth gate as a root-tree switch, not route guards.** With no
  router, gating is `ref.watch(authSessionControllerProvider)` at the root
  `App` widget: loading → branded splash with `CircularProgressIndicator`;
  authenticated → `SeasonsScreen`; unauthenticated → `LoginScreen`.
  Main-app screens are unreachable without a session because the subtree
  does not exist. Justification: satisfies the `flutter-client-authz`
  "every screen route is gated by auth state" requirement without pulling
  routing into this change.
- **D2 — OIDC platform leg via platform channels, injected seam.**
  AuthorizationUi production implementation: `url_launcher` custom tab /
  external browser + `app_links` deep-link capture of the configured
  `OIDC_REDIRECT_URI` scheme. Tests keep injecting fakes via
  `authorizationUiProvider` overrides. The `state` CSRF check and PKCE
  remain in `lib/auth/oidc_client.dart` (unchanged).
- **D3 — Minimal design tokens now, ledger discipline forever.**
  `lib/design/theme.dart` + spacing/typography tokens; default M3
  `ColorScheme` contrast; all new widgets use scheme roles and tokens only
  (machine-checkable via review + widget asserts; the existing
  `FatalConfigErrorApp` hardcoded colors are before-`runApp` scaffolding
  and out of scope — documented, not worked around silently).
- **D4 — Version via `--dart-define=APP_VERSION`.** No `package_info_plus`
  dependency; CI injects the pubspec version at build time; fallback
  constant for local dev builds.
- **D5 — Runtime backend-URI override is dev-flavor only.** Prod-posture:
  `API_BASE` is a build-time pinned configuration and TLS handling is
  pinned-CA (ADR-024); a prod user-editable backend URI would neuter the
  flavor separation and the pinned-CA guarantee. In prod the settings
  dialog shows the active base read-only with explanatory copy. The
  dev override reuses the build's pinned `SecurityContext` — a backend
  whose certificate does not chain to the dev pinned CA simply fails TLS,
  surfaced as an error, never bypassed. Changing the base clears the Drift
  read cache (rows from a different backend must not leak across).
- **D6 — Sign-out invalidates, never deletes silently in-flight work.**
  Sign-out clears tokens AND invalidates the kept-alive session-scoped
  providers + empties the Drift cache so the next session can never render
  the previous user's projections.
