<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design: Login & App Shell

Technical decisions and honest gap documentation for the
`flutter-login-and-app-shell` change. Client-side authority is
`frontend-flutter/AGENTS.md`; where server-owned concerns are touched,
`backend/AGENTS.md` and `backend/openapi.yaml` win.

## 1. Context — what already exists

- `lib/auth/` (from `wire-flutter-oidc-auth`): `AuthSessionController`
  (restore / signIn / signOut over `flutter_secure_storage` +
  `lib/auth/oidc_client.dart` PKCE flow), dev-auth mode
  (`DEV_AUTH_SUB`, frontend flavor only), and the fail-closed
  `NotConfiguredAuthorizationUi` — **the platform browser leg is not wired
  today**. `AppConfig.fromEnvironment` carries flavor, `API_BASE`,
  OIDC settings (all `--dart-define`).
- `lib/src/network/api_client.dart`: pinned-CA `SecurityContext`
  (`withTrustedRoots: false`, both flavors, ADR-024), `buildApiClient`
  constructs the Dio used by the generated `breakdown_api` client;
  `bootstrap()` overrides `dioProvider` with that immutable instance.
- `lib/app.dart`: `MaterialApp` with a single light `ThemeData`
  (`ColorScheme.fromSeed(Colors.teal)`), `home: SeasonsScreen`. No
  `darkTheme`, no `themeMode`.
- Drift cache (`lib/data/cache/`) per `flutter-offline-scope`.

## 2. Auth gate (D1)

```
class App extends ConsumerWidget        // lib/app.dart (rewritten)
  └── ref.watch(authSessionControllerProvider)
        AsyncLoading        → SplashView (brand + CircularProgressIndicator)
        AsyncData(null)    → LoginScreen
        AsyncData(session) → SeasonsScreen
        AsyncError         → LoginScreen with the error surfaced
```

The gate is the *only* place that branches on auth state. A
`FatalConfigErrorApp` (fail-closed startup) is unchanged and precedes it.
Session restore is asynchronous — a pending restore MUST NOT render
`LoginScreen` (flash-of-login problem); loading shows the splash until
restore resolves.

### 2.1 LoginScreen

`lib/features/auth/login_screen.dart` — `ConsumerWidget`; pure widgets
under `lib/features/auth/widgets/` with no Riverpod imports. States:

| Session state | Render |
| --- | --- |
| Dev-auth mode (`config.devAuthMode` && unauthenticated) | Notice card "dev authentication in effect (DEV_AUTH_SUB)" + Continue as <sub> button |
| Real OIDC | Sign-in button → `authSessionController.signIn()`; in-flight shows disable + `CircularProgressIndicator`; `Err(ProblemError)` shows localized copy keyed on `code` (`oidc.*`, `transport.*`) + retry |

Copy rules follow ADR-012/problem-details discipline: never render the
server `detail` or raw exception strings; unknown codes fall back to a
generic error listing the stable `code`.

## 3. OIDC platform leg (D2)

`lib/auth/platform_authorization_ui.dart` implements `AuthorizationUi`:

1. `launch(authorizationUrl)` → `url_launcher` (Custom Tabs on Android;
   the platform-default browser on macOS).
2. `app_links` subscription captures the first redirect matching
   `config.oidcRedirectUri` scheme after `launch` was invoked.
3. The result is returned as `Result<Uri>`; timeout or a redirect for a
   stale `state` returns `Err` (the `state` check itself stays in
   `oidc_client.dart`).

Composition: `authorizationUiProvider` default implementation changes
from `NotConfiguredAuthorizationUi` to `PlatformAuthorizationUi`
(constructed with the resolved redirect URI). Tests override the
provider with fakes — no behavior change to `oidc_client.dart`.

- **Android:** custom scheme registered in the manifest (dev: the
  scheme from `OIDC_REDIRECT_URI`); store-compliant — Custom Tabs
  launches only on explicit user action (the sign-in button).
- **macOS:** `CFBundleURLTypes` registration; macOS support is secondary
  and covered by widget tests; the deep-link mechanism is identical.
- **Battery/store compliance:** no background subscription is held; the
  `app_links` listener only exists while a sign-in is in flight and is
  cancelled on completion.

## 4. No-declarative-routing deviation (documented)

`AGENTS.md` §2 shows a target `lib/routing/` and `MaterialApp.router`,
but a routing solution (package choice, URL scheme, auth-redirect
integration) **requires its own OpenSpec change** per the change
constraints. This change therefore keeps `MaterialApp.home` and uses a
single-tree auth switch. The planned `flutter-hierarchy-navigation`
change stacks its screens with plain `Navigator.push` (Material 3
default transitions) — no new routing packages. A later
`flutter-declarative-routing` change can replace both without altering
requirements (the gate and the pushed flows stay the same from the
user's point of view).

## 5. Design tokens + theming (D3)

- `lib/design/theme.dart`: `seedColor` token (teal, preserving today's
  identity), `AppThemes.light()` / `AppThemes.dark()` built on
  `ColorScheme.fromSeed` (system-contrast, machine-checkable: no
  `Color(` literals outside this file), `themeMode: ThemeMode.system`.
- `lib/design/spacing.dart`: named spacing tokens
  (`space2/space4/space8/…`) — the shell and dialogs use them; existing
  screens are not retro-fitted in this change (honest scope note — the
  seasons screen's `SizedBox(height: 160)` empty-state padding stays
  until `flutter-hierarchy-navigation` touches that area).
- Typography: default M3 `textTheme` only.
- Both themes are golden-tested (light AND dark variants for every new
  surface); both platforms covered by widget tests with
  `TargetPlatform.android` and `TargetPlatform.macOS` variants.
- **Existing-structure conflict, documented not worked around:**
  `FatalConfigErrorApp` in `lib/app.dart` hardcodes `Color(0xFFB71C1C)`
  etc. It necessarily renders without the normal `ThemeData`
  (it may run before the pinning context exists) and is out of scope
  here; a follow-up cosmetics task may move its constants into
  `lib/design/`.

## 6. About / Info dialog

`lib/features/app_info/info_dialog.dart` — Material 3 `AboutDialog`
adaptation; entries (static client copy, l10n-ready):

- **Version** — from `String.fromEnvironment('APP_VERSION')`
  (`--dart-define=APP_VERSION`, injected by CI from pubspec; fallback
  `'unknown'` for local builds). Displayed read-only; not a secret
  (dart-defines are extractable — fine for a version string).
- **License** — "Licensed under GNU AGPL-3.0" + link to the source
  repository (open in browser via `url_launcher`).
- **AI usage notice** — ahead-of-feature legal copy: schedule/script
  import (Phase 3) submits raw schedule text to a **server-side
  configured AI provider**; the app sends that content only when the
  user explicitly submits it, and never contacts AI providers itself.
- Flavors: no.

Accessibility: the dialog renders `ListTile` rows with semantic labels,
respects `textScaler` up to 1.3 without overflow (widget-tested), and
closes on Escape on macOS.

## 7. Settings dialog + runtime backend URI (D4/D5)

`lib/features/app_info/settings_dialog.dart`:

- Shows current API base (read-only field), the flavor, and —
  **dev flavor only** — an editable "Backend URI" field with
  Validation + Reset to default.
- Validation: `Uri.tryParse`, must be absolute; schemes allowed: `http`/
  `https` in dev (`http` permitted because the dev default is
  `http://10.0.2.2:3000`); `https` only in prod — but the prod editor is
  absent entirely (D5), so this is a defensive double-check.
- Persistence: override stored via `flutter_secure_storage` under
  `api_base_override`; `bootstrap()` applies override → `AppConfig.apiBase`
  after `fromEnvironment` and before any client construction.
- Runtime change: `runtimeApiBaseProvider` (`Notifier<String?>`,
  keepAlive) — on save: (1) persist, (2) rebuild the pinned-CA Dio
  through a rebuildable `apiDioProvider` (the pinned `SecurityContext`
  from bootstrap is reused; a mismatched backend fails TLS, surfaced via
  `ProblemError(code: 'transport.*')`, never bypassed), (3) invalidate
  all repository/fetch providers, (4) **clear the Drift cache database**
  (a new base is a different reality; stale rows must not cross
  identities/backends — extends the `flutter-offline-scope` snapshot
  semantics), (5) keep the login session (tokens are IdP-scoped, not
  backend-scoped).
- UI-thread discipline: saving rebuilds clients synchronously
  (cheap object construction); the cache reset runs on Drift's async
  path with a `LinearProgressIndicator` if >100ms (widget-tested).
- **Store compliance / no dark patterns:** the prod dialog hides the
  editor with a visible, plain-language explanation ("The server address
  is set by your organization for security"), not a disabled trap.

### 7.1 Sign-out

`App` menu (overflow on SeasonsScreen `AppBar` until Phase 1b adds a
shell): "Sign out" → `authSessionController.signOut()` → session
providers invalidated + Drift cache emptied (same reset path as a base
change). Keep-alive providers (`dio`, repositories) survive the cache
reset; they are session-agnostic by design (tokens live in the auth
interceptor layer).

### 7.2 Known gap — token lifecycle (honest)

No token refresh or silent re-auth exists in `lib/auth/` today; an
expired access token surfaces as 401 `problem+json` on whichever screen
issues the call, rendered through the standard keyed-on-`code` error
path. Proper refresh + re-auth-on-401 is deferred to its own change
(it touches `AuthTokens` persistence semantics).

## 8. Test-plan mapping (all tiers)

- **Tier 1 unit (no Flutter imports):** override persistence round-trip;
  URI validation function (Ok/Err branches per rule); no-throw in
  `data/` (everything remains `Result`).
- **Tier 2 widget + golden:** gate states (loading/unauth/auth/error),
  LoginScreen (sign-in happy + error + in-flight + dev-auth), dialogs
  (info content presence, settings validation, prod-editor absence),
  each with light/dark goldens and an app-icon-size macOS width variant;
  semantic finders (`find.text`, `byKey`) paired with goldens — never
  `byType` alone.
- **Tier 4 integration:** on-emulator smoke (dev-auth): boot → gate →
  continue → seasons visible → settings → change URI to an unreachable
  value → transport error surfaced → reset. OIDC end-to-end against the
  dev Logto container is exercised manually-per-release (device +
  custom tab), with the fake covering CI.
- Determinism: no wall-clock gating; async seams injected.
