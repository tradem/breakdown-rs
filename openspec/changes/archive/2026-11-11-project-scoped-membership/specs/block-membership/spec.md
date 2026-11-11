<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# block-membership Delta (project-scoped-membership)

## MODIFIED Requirements

### Requirement: Roles are block-scoped domain values

Roles SHALL be modeled as a domain `Role` enum local to the membership Bounded
Context. A **block membership** SHALL grant a role scoped to a single
`BlockId`; it SHALL NOT be a global attribute of the user, nor a season-scoped
one. The same `UserId` MAY hold different roles in different blocks — including
two blocks of the same season, concurrently — because costume-department staff
rotate roles at block boundaries.

Independently of block membership, a **project-scoped role grant** SHALL exist
(see "Project-scoped costume role grant"), because a role that can only be
attached to a block makes every block-less season role-less by construction.
An authorization check SHALL resolve the effective role from both scopes, block
first; neither scope SHALL overwrite the other's rows.

#### Scenario: Same user holds different roles across blocks of one season
- **WHEN** a `UserId` is an active member of Block 1 and Block 2 of the same season
- **THEN** the system MAY record a different `Role` for that user in each block (e.g. `costume_designer` in Block 1 and `wardrobe_supervisor` in Block 2), and a role change in one block SHALL NOT affect the other

#### Scenario: A block-scoped role and a project-scoped grant coexist
- **WHEN** a `UserId` holds `costume_assistant` in Block 1 and a project-scoped
  `costume_designer` grant on Block 1's project
- **THEN** both rows SHALL exist, a check inside Block 1's season SHALL resolve
  to the block-scoped `costume_assistant` (block first), and a check inside a
  block-less season of the same project SHALL resolve to the project-scoped
  `costume_designer`

## ADDED Requirements

### Requirement: Project-scoped costume role grant

The system SHALL support a role grant scoped to a `ProjectId` rather than a
`BlockId`, carried by its own stream
(`project_membership-{project_id}-{user_id}`) and its own read-model projection
(`projection_project_membership`). The grant SHALL be restricted to the
costume-department roles (`costume_designer`, `wardrobe_supervisor`,
`costume_assistant`); any other role SHALL be rejected by the aggregate, not
only by the transport layer. Grants SHALL be idempotent: re-granting an active
role SHALL be a no-op, and revoking an absent grant SHALL be a no-op.

#### Scenario: Grant a project-scoped costume role
- **WHEN** a caller holding a project-scoped costume role grants
  `wardrobe_supervisor` to another user on the same project
- **THEN** `ProjectRoleGranted` SHALL be emitted once and the projection SHALL
  expose the active grant for that `(project_id, user_id)`

#### Scenario: A non-costume role cannot be granted at project scope
- **WHEN** a grant names a role outside the costume-department allowlist
- **THEN** the command SHALL be refused and no event SHALL be appended

### Requirement: Season creation bootstraps the creator's project role

Creating a season SHALL bootstrap a project-scoped `costume_designer` grant for
its creator, idempotently — mirroring the block-creation `OwnerBootstrapped`
precedent — so that a project has an accountable costume role from its first
season, including a season that never gains a block. A replay or a second
season in the same project SHALL NOT duplicate the grant.

#### Scenario: The first season of a project creates the earliest project role
- **WHEN** a season is created in a project that has no project-scoped membership
- **THEN** a `ProjectOwnerBootstrapped`-equivalent grant (`costume_designer`)
  SHALL exist for the creator, and the creator SHALL pass a season-scoped
  costume-dept check on that season even though it has no block

#### Scenario: Bootstrap is idempotent across replays
- **WHEN** the season-creation path runs twice for the same season and creator
- **THEN** exactly one active project-scoped grant SHALL exist
