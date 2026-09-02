<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-auth-shell Specification (delta)

## ADDED Requirements

### Requirement: Root Auth Gate on Application Entry
The application root (`App`) SHALL branch on
`authSessionControllerProvider`: `AsyncLoading` renders a splash with a
`CircularProgressIndicator`; `AsyncData(null)` renders `LoginScreen`;
`AsyncData(session)` renders the seasons screen; `AsyncError` renders
`LoginScreen` with the error surfaced. No main-app screen SHALL be
reachable without a resolved authenticated session.

#### Scenario: Session restore is in flight
- **WHEN** the app starts and restore has not resolved.
- **THEN** the splash (not `LoginScreen`) is visible until the
  `AsyncValue` settles.

#### Scenario: Signed-out user opens the app
- **WHEN** no tokens are stored (`AsyncData(null)`).
- **THEN** only `LoginScreen` is rendered; the seasons list makes no
  network call.

#### Scenario: Sign-out returns to the login gate
- **WHEN** an authenticated user signs out.
- **THEN** tokens are cleared, the Drift read cache is emptied, and the
  root recomposes to `LoginScreen`.

### Requirement: LoginScreen Presentation and Sign-In Dispatch
`LoginScreen` SHALL be a `ConsumerWidget` with sign-in dispatch delegated
to the auth session controller. Sign-in in flight disables the action
and shows a `CircularProgressIndicator`. Dev-auth mode (`devAuthMode`)
SHALL show a notice naming the effective `DEV_AUTH_SUB` and a single
Continue action instead of the OIDC button.

#### Scenario: OIDC sign-in completes
- **WHEN** the user taps Sign in and the redirected code exchange
  succeeds.
- **THEN** `AuthSessionController` stores tokens and the root gate
  renders the main app; the login screen never mints a session itself.

#### Scenario: Sign-in fails
- **WHEN** `signIn()` returns `Err(ProblemError)`.
- **THEN** the login screen renders localized copy keyed on the problem
  `code` (never the server `detail` or a raw exception string) plus a
  retry affordance.

### Requirement: Platform Authorization UI Wiring
A production `AuthorizationUi` implementation SHALL launch the
authorization URL in the platform browser (Custom Tabs on Android,
default browser on macOS) only on explicit user action, and SHALL
capture the deep-link redirect for the configured `OIDC_REDIRECT_URI`
scheme while the sign-in is in flight. No listener SHALL remain after
completion or failure.

#### Scenario: AuthorizationUi provider is wired
- **WHEN** the composition root initializes in a device build.
- **THEN** `authorizationUiProvider` resolves to the platform
  implementation; the fail-closed `NotConfiguredAuthorizationUi` is used
  only when tests inject it.

#### Scenario: Sign-in fails
- **WHEN** authorizationUrl launch or redirect capture fails.
- **THEN** the failure surfaces as `Err(ProblemError)` from `signIn()`
  with a stable `oidc.*` code; the login error copy renders it.
