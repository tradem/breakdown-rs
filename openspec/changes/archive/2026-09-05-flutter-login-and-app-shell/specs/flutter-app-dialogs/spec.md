<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-app-dialogs Specification (delta)

## ADDED Requirements

### Requirement: Info Dialog Contents
The app SHALL offer an About/Info dialog covering, in plain language:
(a) the application version, (b) the license (GNU AGPL-3.0) with a link
to the source repository, and (c) an AI usage notice stating that
schedule/script import features submit user-provided text to a
server-side configured AI provider and that the app itself never
communicates with an AI provider directly.

#### Scenario: Version display
- **WHEN** the dialog renders in a build where CI injected
  `--dart-define=APP_VERSION`.
- **THEN** the version shown equals that value; without it, the fallback
  `'unknown'` shows.

#### Scenario: Store review checks AI disclosure
- **WHEN** the store submission checklist asks whether the app discloses
  AI data use.
- **THEN** the info dialog references it and the app's manifest does not
  declare any AI-related runtime permission; no AI network call exists in
  this phase.

### Requirement: Settings Dialog with Dev-Only Backend-URI Override
The settings dialog SHALL display the active API base and flavor. In the
`dev` flavor it SHALL additionally offer an editable backend-URI field
with validation (absolute `http`/`https` URI) and a reset-to-default
action. In the `prod` flavor the editable field SHALL NOT be present
and its absence SHALL be explained in plain language.

#### Scenario: Dev user sets a valid override
- **WHEN** a dev-flavor user saves a valid absolute URI.
- **THEN** it is persisted in `flutter_secure_storage`, the pinned-CA
  Dio is rebuilt against it (same pinned CA set), all read providers are
  invalidated, and the Drift read cache is emptied — subsequent screens
  fetch from the new base.

#### Scenario: Backend behind a different certificate
- **WHEN** the overridden backend's certificate does not chain to the
  dev flavor's pinned CA set.
- **THEN** requests fail with a transport-level `ProblemError` surfaced
  through the standard error copy; certificate verification is never
  disabled or relaxed.

#### Scenario: Invalid or unreachable URI rejected client-side
- **WHEN** a non-absolute string or an unreachable host is saved.
- **THEN** the save action validates and either rejects malformed input
  inline (no network call) or surfaces the subsequent transport error
  keyed on `code` — never a crash and never a silent discard.

#### Scenario: Prod build
- **WHEN** the `prod` flavor renders the settings dialog.
- **THEN** the backend-URI editor is absent; the active base shows
  read-only with explanatory copy ("set by your organization for
  security").

### Requirement: Runtime Override Applies at Next Bootstrap
A persisted backend-URI override SHALL be applied in `bootstrap()` after
`AppConfig.fromEnvironment` and before any `Dio`/repository is
constructed, so no request ever targets the compile-time base when an
override is stored. **The override is flavor-guarded:** it is applied
ONLY when `config.flavor == Flavor.dev`. Android ships a single
application ID with no product flavors, so an unscoped `api_base_override`
would let a production release inherit a dev `http` base — bypassing both
the compile-time endpoint and TLS pinning. In `prod` a stored override is
ignored AND cleared on boot; the compile-time HTTPS base is always used.
**Cleartext overrides never carry credentials:** in the `dev` flavor an
absolute `http` URI is accepted only for emulator/loopback hosts
(`10.0.2.2`, `127.0.0.1`, `localhost`), and for every cleartext request
the auth interceptor withholds the bearer token — the session credential
is attached only over HTTPS to the pinned-CA transport. Any other `http`
override is rejected by validation with localized copy (CWE-319: no
session credential is ever transmitted in the clear to an arbitrary
host).

#### Scenario: Cold start with override
- **WHEN** the app boots in the `dev` flavor with a stored override.
- **THEN** the first network call targets the overridden base.

#### Scenario: Production cold start ignores a stored override
- **WHEN** a `prod` build boots with a stored override (e.g. left over
  from a dev install over the same application ID).
- **THEN** the compile-time HTTPS base is used, the stored override is
  cleared, and no request is ever made to the overridden (possibly
  cleartext) address.
