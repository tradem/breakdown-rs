<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# api-authorization Specification

## Purpose
TBD - created by archiving change add-oidc-auth-and-membership. Update Purpose after archive.
## Requirements
### Requirement: Authorization before write command dispatch
For write commands belonging to a production scope (e.g. `CreateScene`, `CreateCharacter`, `CreateCostume`, and their updates), the API layer SHALL consult the **block-membership** read model for the caller's role in the **active `BlockId` of the request** before dispatching the command, and SHALL reject the request with HTTP 403 when the authenticated `CurrentUser` is not an active member of that block. The active Block SHALL be conveyed by the request (request path/header/body or a UI session scope); the membership context itself only needs the resolved `BlockId`. Authorization is **action-scoped** (the block the caller is working in), not data-scoped.

#### Scenario: Member is allowed to dispatch a write command
- **WHEN** an authenticated `CurrentUser` dispatches a write command while the request's active `BlockId` is one of which they are an active member
- **THEN** the API layer SHALL forward the command to the write side

#### Scenario: Non-member is denied
- **WHEN** an authenticated `CurrentUser` dispatches a write command while the request's active `BlockId` is one of which they are not an active member
- **THEN** the API layer SHALL reject the request with HTTP 403 and SHALL NOT dispatch the command

### Requirement: Block-scoped reads are gated by membership
For block-scoped read endpoints that list or detail resources belonging to a `BlockId`, the API layer SHALL deny the request with HTTP 403 when the authenticated `CurrentUser` is not an active member of that block.

#### Scenario: Member can read block data
- **WHEN** an authenticated `CurrentUser` requests block-scoped read data for a `BlockId` of which they are an active member
- **THEN** the API layer SHALL return the requested data

#### Scenario: Non-member cannot read block data
- **WHEN** an authenticated `CurrentUser` requests block-scoped read data for a `BlockId` of which they are not an active member
- **THEN** the API layer SHALL reject the request with HTTP 403

### Requirement: Authorization lives in the API layer, not in core
The authorization policy SHALL be implemented in `crates/api` and SHALL NOT require `core` aggregates to receive or inspect the caller. `core` aggregates SHALL remain unaware of the authenticated user except where, in a future change, a specific command's domain logic explicitly depends on the actor.

#### Scenario: Core aggregates are not coupled to authorization
- **WHEN** the authorization policy decides whether to dispatch a command
- **THEN** the decision SHALL be made using the membership read model in the API layer, and the dispatched command SHALL be the same command type already accepted by the aggregate

### Requirement: Role-based policy is additive and explicit
Where the policy depends on a specific `Role` (e.g. "only a `costume_designer` may do X"), the rule SHALL be expressed explicitly against the membership read model and SHALL fail closed (deny) when the caller's role does not match. Initial v1 may enforce membership-only policy without role distinctions; role-distinct rules SHALL be added only as explicit, individually-documented behaviors.

#### Scenario: Role-distinct rule fails closed
- **WHEN** a role-distinct authorization rule is configured and the caller's `Role` does not match the required role
- **THEN** the API layer SHALL reject the request with HTTP 403

### Requirement: Tenancy boundary is per `SeriesId`, deferred (no v1 enforcement)
The system defines its tenant boundary as **per `SeriesId`** (a production today; a future "movie" iteration is also a `Series`). In v1 the deployment is effectively single-tenant and the system SHALL NOT enforce cross-tenant isolation at the domain layer; the IdP organization check remains upstream at login (ADR-010). The authorization design SHALL leave an explicit, documented seam (a future active-series scope + policy check) so that per-`SeriesId` isolation can be added as an additive follow-up change without a rewrite.

#### Scenario: Single-tenant v1 is allowed
- **WHEN** a request is authorized in a v1 single-tenant deployment
- **THEN** the policy SHALL decide based on the active `BlockId` membership only, with no cross-tenant check

### Requirement: Season-scoped checks resolve block membership first, then a project-scoped grant

Every season-scoped authorization check that accepts the costume-department
roles SHALL resolve the caller's effective role as: an active block membership
in a block of that season, else an active project-scoped costume role on the
season's `project_id`, else deny. Resolution SHALL live in one
`MembershipRepository` method (`effective_costume_role_in_season`); handlers
and policies SHALL NOT re-implement the precedence.

The check SHALL fail closed: a projection miss, a repository error or an
unresolvable `project_id` SHALL deny, never allow.

#### Scenario: A project-scoped costume role authorizes a block-less season
- **WHEN** a caller holds an active project-scoped `costume_designer` grant on
  the season's project and the season has no blocks
- **THEN** a season-scoped costume-dept check on that season SHALL allow

#### Scenario: A caller with no role in either scope is denied
- **WHEN** the caller holds neither a block membership in the season nor a
  project-scoped costume role on its project
- **THEN** the check SHALL deny and the write SHALL answer `403` with the
  existing problem code (`ai-import.forbidden` for the import upload)

#### Scenario: A projection miss does not widen access
- **WHEN** the project-scoped projection has no row for the caller
- **THEN** the check SHALL deny (unchanged pre-change behavior for callers
  without a project grant)

### Requirement: The report-archive check does not gain the project fallback

`has_active_report_archive_role_in_season` SHALL keep its block-only resolution
and its narrower two-role allowlist (`costume_designer`,
`wardrobe_supervisor`). Manual archive remediation SHALL NOT become reachable
through a project-scoped grant.

#### Scenario: A project-scoped role cannot archive a report manually
- **WHEN** a caller holds only a project-scoped `costume_designer` grant and
  attempts a manual report archive in a season with no block
- **THEN** the check SHALL deny

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

