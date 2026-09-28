# flutter-app-dialogs Specification

## Purpose
TBD - created by archiving change flutter-login-and-app-shell. Update Purpose after archive.
## Requirements
### Requirement: Info Dialog Contents
The app SHALL offer an About/Info dialog covering, in plain language:
(a) the application version, (b) the license (GNU AGPL-3.0) with a link
to the source repository, and (c) an AI usage notice stating that
schedule/script import features submit user-provided text to a
server-side configured AI provider and that the app itself never
communicates with an AI provider directly. The AI usage notice SHALL be
the doorway to a dedicated About-AI screen (`AiDisclosureScreen`) that
carries the expanded EU AI Act transparency disclosure; the dialog notice
SHALL remain and SHALL navigate to the screen on tap.

The About-AI screen SHALL carry six content blocks: (1) purpose of the
AI feature, (2) data flow of the import (device → backend → configured
provider → drafts → preview → apply), (3) provider/model naming read from
the caller's configured non-secret `AiConfigView` with an honest
degradation state when none is configured, (4) payload retention (imported
document payloads are garbage-collected after 7 days), (5) the EU AI Act
reference (Art. 4 AI literacy support, Art. 50 transparency, (EU)
2024/1689), and (6) the AGPL-3.0 / source-repository link. All copy SHALL
be localized ARB catalog copy; the screen spec SHALL live at
`docs/design/screens/about-ai.md` with a PlantUML Salt wireframe.

#### Scenario: Version display
- **WHEN** the dialog renders in a build where CI injected
  `--dart-define=APP_VERSION`.
- **THEN** the version shown equals that value; without it, the fallback
  `'unknown'` shows.

#### Scenario: AI notice navigates to the About-AI screen
- **WHEN** the user taps the dialog's AI notice.
- **THEN** the dedicated About-AI screen pushes over the dialog context and
  the dialog closes.

#### Scenario: Provider/model naming configured
- **WHEN** the About-AI screen renders and the caller has a configured
  `AiConfigView`.
- **THEN** block (3) names the configured provider and assistant model
  (non-secret wire values only; no vault reference, no prompt text).

#### Scenario: Provider/model naming unconfigured
- **WHEN** the About-AI screen renders with no configured `AiConfigView`
  (or the config fetch fails).
- **THEN** block (3) renders its honest degradation copy ("no AI
  configuration for this account") — no provider/model is invented.

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
