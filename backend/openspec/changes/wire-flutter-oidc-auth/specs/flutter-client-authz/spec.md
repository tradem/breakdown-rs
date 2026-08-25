<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: currentMembershipProvider for AUTHZ-GATE Checks
A `currentMembershipProvider` SHALL expose the authenticated user's
membership/role state so that gated backend calls run a client-side role
check before any network call. A new gated handler call without a
`// AUTHZ-GATE:` comment and a `currentMembershipProvider` check is
rejected at review.

#### Scenario: User lacks upload role
- **WHEN** a user without an active continuity role taps the capture action.
- **THEN** the action short-circuits client-side via
  `ref.read(currentMembershipProvider).valueOrNull`, shows a localized 403
  narrative, and never issues the `POST .../continuity-photos` request.

### Requirement: Cert Pinning Matches Backend Pinned-CA Stance
The HTTP client SHALL pin TLS roots per flavor (ADR-024), sourced from
`--dart-define`. No `danger_accept_invalid_certs`-equivalent in any code
path.

#### Scenario: A debug build bypasses TLS verification
- **WHEN** a committed code path disables verification outside the dev
  flavor's pinned-CA set.
- **THEN** review rejects it; dev trusts go into the dev flavor's pinned CA
  set only.
