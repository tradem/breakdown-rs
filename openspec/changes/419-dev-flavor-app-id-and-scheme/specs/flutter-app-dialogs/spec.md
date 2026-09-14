<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# flutter-app-dialogs Delta (issue #419 — distinct flavor application IDs)

## MODIFIED Requirements

### Requirement: Runtime Override Applies at Next Bootstrap
A persisted backend-URI override SHALL be applied in `bootstrap()` after
`AppConfig.fromEnvironment` and before any `Dio`/repository is
constructed, so no request ever targets the compile-time base when an
override is stored. **The override is flavor-guarded:** it is applied
ONLY when `config.flavor == Flavor.dev`. Android ships DISTINCT
application IDs per Gradle flavor since issue #419 (prod:
`rs.breakdown.frontend_flutter`; dev: `rs.breakdown.frontend_flutter.dev`
via `applicationIdSuffix`), so a production release no longer reads a dev
install's secure storage at all — the prod-side ignore-and-clear guard is
retained as defense-in-depth against storage misconfiguration. In `prod`
a stored override is ignored AND cleared on boot; the compile-time HTTPS
base is always used. **Cleartext overrides never carry credentials:** in
the `dev` flavor an absolute `http` URI is accepted only for
emulator/loopback hosts (`10.0.2.2`, `127.0.0.1`, `localhost`), and for
every cleartext request the auth interceptor withholds the bearer token —
the session credential is attached only over HTTPS to the pinned-CA
transport. Any other `http` override is rejected by validation with
localized copy (CWE-319: no session credential is ever transmitted in the
clear to an arbitrary host).

#### Scenario: Cold start with override
- **WHEN** the app boots in the `dev` flavor with a stored override.
- **THEN** the first network call targets the overridden base.

#### Scenario: Production cold start ignores a stored override
- **WHEN** a `prod` build boots with a stored override (defense-in-depth:
  the prod application ID no longer shares storage with a dev install).
- **THEN** the compile-time HTTPS base is used, the stored override is
  cleared, and no request is ever made to the overridden (possibly
  cleartext) address.
