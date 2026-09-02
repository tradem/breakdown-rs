<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Client-Side AUTHZ-GATE Before Gated Calls
Every screen route SHALL be gated by auth state, and every call to a
handler-internal-authz-gated backend endpoint (photo upload, photo byte
fetch, photo delete, continuity-photo handlers) SHALL run a client-side
role/membership check via a `currentMembershipProvider` *before* any network
call is made. This is the client-side analog of the backend's
`// AUTHZ-GATE:` handler-internal authorization pattern. The login route,
the OIDC callback route, and the recovery route are the sole exceptions:
they SHALL remain publicly reachable before a session exists, so the user can
establish one.

#### Scenario: User lacks upload role
- **WHEN** a user without an active costume/continuity role taps the
  "Continuity Photo" capture action.
- **THEN** the action short-circuits client-side
  (`ref.read(currentMembershipProvider).valueOrNull` denies), shows a
  localized 403 narrative, and never issues the `POST .../continuity-photos`
  request.

#### Scenario: A new photo handler is added without a gate
- **WHEN** a PR adds a new endpoint call under an `Authenticated`-only route
  that performs a privileged action, without a `// AUTHZ-GATE:` comment and
  a `currentMembershipProvider` check.
- **THEN** review rejects it (mirrors the backend `grep AUTHZ-GATE`
  verification).

### Requirement: OIDC Token Storage and Cert Pinning
OIDC tokens SHALL be stored in `flutter_secure_storage` (never plaintext prefs);
the HTTP client SHALL pin TLS roots matching the backend's pinned-CA stance
(ADR-024), configured via `--dart-define`/flavor. No `danger_accept_invalid_certs`
equivalent is permitted in any client code path.

#### Scenario: A debug build is configured to bypass TLS verification
- **WHEN** a developer adds an "allow self-signed" convenience in any committed
  code path or flavor.
- **THEN** review rejects it; development trusts go into the dev flavor's
  pinned CA set, never into a disable-verification switch.

### Requirement: No Hardcoded Secrets
No secrets (OIDC client secrets, API keys, Garage credentials) SHALL be
committed to — or embedded in — the Flutter binary. `gitleaks` scans `.dart`,
`.yaml`, and `.arb` files. `--dart-define` carries only non-secret
configuration and public client identifiers (API base URL, OIDC issuer,
public client id, pinned-CA PEM); because Flutter embeds `--dart-define`
values in the compiled artifact where users can extract them, confidential
credentials (Garage keys, confidential-client secrets) stay server-side and
are never passed to the app.

#### Scenario: A developer passes a server-side credential via --dart-define
- **WHEN** a build embeds a Garage key or a confidential OIDC client secret
  through `--dart-define`.
- **THEN** review rejects it: `--dart-define` values are extractable from the
  compiled artifact, so those credentials must stay server-side; only public
  identifiers and non-secret configuration may be embedded.

#### Scenario: A developer hardcodes a client secret
- **WHEN** gitleaks finds a literal credential in a `.dart`/`.yaml` file.
- **THEN** CI fails (mirrors backend supply-chain posture).
