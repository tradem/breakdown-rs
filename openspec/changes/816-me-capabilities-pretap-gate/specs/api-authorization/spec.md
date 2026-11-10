<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# api-authorization

## ADDED Requirements

### Requirement: Global Capability Self-Report Is Authenticated-Only and Reports the Enforcement Predicates

`GET /v1/me/capabilities` SHALL report the caller's two deployment-scoped
capabilities — `has_active_credential_role` and `has_active_ops_role` — as
booleans with status 200. The middleware SHALL classify the route as
`Authenticated` (no block membership: a deployment-scoped capability says
nothing about the caller's `X-Active-Block`). The handler SHALL resolve both
values through the injected `AuthorizationPolicy` — the same instance the
middleware enforces with — so the reported answer cannot drift from enforcement
(the ops arm therefore includes the deployment's `OPS_ADMIN_SUBS` bootstrap
allowlist). The endpoint SHALL NOT answer 403: it performs no privileged action,
and its whole purpose is to let a client distinguish "denied" from "unknown"
before it acts. A read-model failure SHALL surface as an error response carrying
a registered problem code, never as `false`.

#### Scenario: A caller without the credential role

- **WHEN** an authenticated caller with no active credential role requests the
  route
- **THEN** the response is 200 with `has_active_credential_role: false` (not a
  403), so the client can state the denial before any gated call.

#### Scenario: A predicate read fails

- **WHEN** the membership read model fails while resolving either predicate
- **THEN** the response is an error carrying an existing registered problem
  code (never `200 { "has_active_credential_role": false }`) — a broken
  predicate must not be indistinguishable from a denial.

#### Scenario: Ops bootstrap allowlist

- **WHEN** the caller's OIDC `sub` is on the deployment's `OPS_ADMIN_SUBS`
  allowlist and holds no `ops_admin` membership row yet
- **THEN** `has_active_ops_role` is `true`, because the handler resolves through
  the policy (which consults the allowlist) rather than the repository.

#### Scenario: A new route under `/me`

- **WHEN** a future handler mounts `/me/…`
- **THEN** `requirement_for` falls back to `BlockMember` unless that exact path
  is classified explicitly — the `/me/capabilities` arm is an equality match,
  not a prefix wildcard.
