<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Login & App Shell

## 1. Design tokens & theming
- [ ] 1.1 `lib/design/theme.dart` — `AppThemes.light()` / `AppThemes.dark()`
       (`ColorScheme.fromSeed`, teal seed token) and
       `lib/design/spacing.dart` token set
- [ ] 1.2 `lib/app.dart` — `App` renders Consumer with `theme`,
       `darkTheme`, `themeMode: ThemeMode.system` (replace the inline
       light-only `ThemeData`; keep `FatalConfigErrorApp` unchanged —
       documented deviation, design.md §5)
- [ ] 1.3 Widget tests: dark-mode switch without restart; golden set
       (light + dark) for gate, login, and dialogs; `textScaler 1.3` no-
       overflow assertions

## 2. Auth gate
- [ ] 2.1 `lib/app.dart` — root ConsumerWidget switch over
       `authSessionControllerProvider` (loading→splash, `null`→LoginScreen,
       session→SeasonsScreen, error→LoginScreen+error); splash is a
       design-token widget with `CircularProgressIndicator`
- [ ] 2.2 Widget tests: all four gate states; assert no main-app network
       call happens in the unauthenticated state (fake repository
       call-count = 0)
- [ ] 2.3 Golden tests (light+dark) for splash + gate states

## 3. Login screen & OIDC platform leg
- [ ] 3.1 `features/auth/login_screen.dart` — `ConsumerWidget`; pure
       widgets under `features/auth/widgets/` (no Riverpod imports); OIDC
       sign-in, in-flight disabled state + progress, dev-auth notice +
       Continue, localized error copy keyed on `code` with retry
- [ ] 3.2 `lib/auth/platform_authorization_ui.dart` — `AuthorizationUi`
       via `url_launcher` (Custom Tabs) + `app_links` redirect capture;
       listener lifecycle tied to the in-flight sign-in only; returns
       `Result<Uri>`; `authorizationUiProvider` default becomes
       `PlatformAuthorizationUi`
- [ ] 3.3 Android manifest + macOS `Info.plist` custom-scheme
       registration for `OIDC_REDIRECT_URI`, with the Android scheme
       injected at build time (Gradle `manifestPlaceholder` derived
       from the same source as the `--dart-define`) so the native
       registration cannot drift from the configured URI; a mismatch
       fails the build, and a device/emulator test confirms the
       redirect is delivered to `app_links`
- [ ] 3.4 Add `url_launcher` + `app_links` to `pubspec.yaml`
- [ ] 3.5 Unit tests: fake `AuthorizationUi` driving `signIn()` Ok/Err
       branches — the platform fake covers exactly the three platform
       failure modes (browser-launch, timeout, redirect-capture), and
       the `state` mismatch is asserted at the `oidc_client` level
       (`oidc.state_mismatch`), not in the platform contract
- [ ] 3.6 Widget tests + goldens: LoginScreen happy/error/in-flight/
       dev-auth (light + dark); semantic finders paired with goldens
- [ ] 3.7 Integration test (emulator, dev-auth): boot → gate → continue →
       seasons render; a second cold-start smoke with the OIDC fake

## 4. App-shell chrome (identity, sign-out)
- [ ] 4.1 AppBar overflow menu on the seasons screen: user identity
       (session `sub`), About, Settings, Sign out
- [ ] 4.2 `signOut` → clear tokens, empty Drift cache, invalidate
       session-scoped providers, root recomposes to `LoginScreen`
- [ ] 4.3 Unit + widget tests: sign-out state machine (Ok/Err), cache
       emptied exactly once, no post-signout projection render

## 5. Info dialog
- [ ] 5.1 `features/app_info/info_dialog.dart` — version
       (`--dart-define=APP_VERSION`, fallback `'unknown'`), AGPL-3.0
       license + source link (opens via `url_launcher`), AI usage notice
- [ ] 5.2 Widget tests + goldens (light+dark): content presence,
       textScale 1.3 no overflow, Escape close on macOS

## 6. Settings dialog & runtime API base
- [ ] 6.1 `lib/app_config.dart` — read `APP_VERSION`; `bootstrap()`
       applies persisted `api_base_override` after `fromEnvironment`
       before client construction
- [ ] 6.2 `data/settings/api_base_override_store.dart` — secure-storage
       read/write/clear, `Result`-typed, unit-tested Ok/Err
- [ ] 6.3 Rebuildable `apiDioProvider` (pinned `SecurityContext` reused)
       + `runtimeApiBaseProvider` (Notifier); save path goes through the
       shared reset coordinator: persist → rebuild Dio → fence
       in-flight reads (generation/cancellation barrier) → await Drift
       clear → invalidate read providers, progress surfaced. The same
       coordinator is used by sign-out (section 4), and a unit test
       asserts a late pre-clear write is discarded, not persisted
- [ ] 6.4 `features/app_info/settings_dialog.dart` — current base +
       flavor display; dev-only URI editor with inline validation +
       reset; prod variant with explanatory read-only copy
- [ ] 6.5 Unit tests: URI validation Ok/Err per rule; override
       round-trip; bootstrap pre-application ordering
- [ ] 6.6 Widget tests + goldens: dev dialog (valid/invalid input,
       reset), prod dialog (editor absent); transport-failure copy keyed
       on `code`
- [ ] 6.7 Integration test: change base to unreachable URI → transport
       error surfaced on the affected screen → reset recovers

## 7. Housekeeping
- [ ] 7.1 SPDX headers on all new files; `dart format`,
       `flutter analyze`, `breakdown_lints_runner`,
       `flutter test --coverage` + `coverde` gate, gitleaks clean
- [ ] 7.2 `openspec` task/spec coverage audit: every scenario in
       `flutter-auth-shell`, `flutter-design-tokens`,
       `flutter-app-dialogs` has a passing test
