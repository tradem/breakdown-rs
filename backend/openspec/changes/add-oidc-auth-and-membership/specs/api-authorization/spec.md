## ADDED Requirements

### Requirement: Authorization before write command dispatch
For project-scoped write commands (e.g. `CreateScene`, `CreateCharacter`, `CreateCostume`, `CreateCalculation`, and their updates), the API layer SHALL consult the membership read model before dispatching the command and SHALL reject the request with HTTP 403 when the authenticated `CurrentUser` is not an active member of the command's target `ProjectId`.

#### Scenario: Member is allowed to dispatch a write command
- **WHEN** an authenticated `CurrentUser` dispatches a project-scoped write command targeting a `ProjectId` of which they are an active member
- **THEN** the API layer SHALL forward the command to the write side

#### Scenario: Non-member is denied
- **WHEN** an authenticated `CurrentUser` dispatches a project-scoped write command targeting a `ProjectId` of which they are not an active member
- **THEN** the API layer SHALL reject the request with HTTP 403 and SHALL NOT dispatch the command

### Requirement: Project-scoped reads are gated by membership
For project-scoped read endpoints that list or detail resources belonging to a `ProjectId`, the API layer SHALL deny the request with HTTP 403 when the authenticated `CurrentUser` is not an active member of that project.

#### Scenario: Member can read project data
- **WHEN** an authenticated `CurrentUser` requests project-scoped read data for a `ProjectId` of which they are an active member
- **THEN** the API layer SHALL return the requested data

#### Scenario: Non-member cannot read project data
- **WHEN** an authenticated `CurrentUser` requests project-scoped read data for a `ProjectId` of which they are not an active member
- **THEN** the API layer SHALL reject the request with HTTP 403

### Requirement: Authorization lives in the API layer, not in core
The authorization policy SHALL be implemented in `crates/api` and SHALL NOT require `core` aggregates to receive or inspect the caller. `core` aggregates SHALL remain unaware of the authenticated user except where, in a future change, a specific command's domain logic explicitly depends on the actor.

#### Scenario: Core aggregates are not coupled to authorization
- **WHEN** the authorization policy decides whether to dispatch a command
- **THEN** the decision SHALL be made using the membership read model in the API layer, and the dispatched command SHALL be the same command type already accepted by the aggregate

### Requirement: Role-based policy is additive and explicit
Where the policy depends on a specific `Role` (e.g. "only a `Kostümbildner` may do X"), the rule SHALL be expressed explicitly against the membership read model and SHALL fail closed (deny) when the caller's role does not match. Initial v1 may enforce membership-only policy without role distinctions; role-distinct rules SHALL be added only as explicit, individually-documented behaviors.

#### Scenario: Role-distinct rule fails closed
- **WHEN** a role-distinct authorization rule is configured and the caller's `Role` does not match the required role
- **THEN** the API layer SHALL reject the request with HTTP 403
