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

