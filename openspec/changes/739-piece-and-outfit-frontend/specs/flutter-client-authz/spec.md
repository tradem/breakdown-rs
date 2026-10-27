<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-client-authz Delta

## ADDED Requirements

### Requirement: Outfit Command Gating

Every outfit command surfaced by the client (create, create-variant,
rename, notes, add/remove piece, photo upload/delete) SHALL run the
client-side AUTHZ-GATE mirror before issuing the request: the current
membership's costume-department predicate for the owning **project**
(issue #535 boundary — `hasActiveCostumeRoleInSeries`, wire name and
capability list unchanged) SHALL be consulted, awaited, and a pending
fetch SHALL disable the affordance rather than deny it. A denial SHALL
render the localized 403 narrative and SHALL NOT dispatch the request.
No client-side re-implementation of the role resolution — the predicate
comes from the backend-computed capability list.

#### Scenario: Pending membership disables instead of denying

- **WHEN** the user opens an outfit detail while the membership fetch is
  still in flight
- **THEN** the write affordances are disabled (no request is issued, no
  403 narrative is shown) and they enable once the predicate resolves
  positively.

#### Scenario: Denial never reaches the network

- **WHEN** the membership resolves without the costume-department role
- **THEN** tapping any outfit write affordance shows the localized 403
  narrative and the request counter for the outfit mutation route stays
  at zero.

#### Scenario: Gate comment is auditable

- **WHEN** the outfit dispatch sites are reviewed
- **THEN** each carries a `// AUTHZ-GATE:` comment referencing the
  membership gate, so `grep AUTHZ-GATE` lists the outfit commands next to
  the existing photo and scene-beat commands.
