## ADDED Requirements

### Requirement: Project Membership aggregate
The system SHALL model project-scoped membership as a `ProjectMembership` aggregate, event-sourced via `kameo_es`, scoped per `ProjectId` and holding a map of `UserId -> Role`. A membership aggregate SHALL belong to exactly one `ProjectId`.

#### Scenario: Aggregate is keyed by project
- **WHEN** a `ProjectMembership` aggregate is instantiated
- **THEN** its identity SHALL consist of a single `ProjectId`, and it SHALL reference members only relative to that project

### Requirement: Member invitation
The system SHALL allow inviting a `UserId` to a project via an `InviteMember` command, emitting a `MemberInvited` event recording the invitee and proposed role, without granting membership until the invitation is accepted.

#### Scenario: Inviting a new member
- **WHEN** an `InviteMember { project_id, user_id, role }` command is dispatched and the `user_id` is not yet a member
- **THEN** the aggregate SHALL emit `MemberInvited { project_id, user_id, role }` and SHALL NOT yet consider the user an active member

#### Scenario: Re-inviting an existing invitee is rejected
- **WHEN** an `InviteMember` command targets a `user_id` that already has a pending invitation
- **THEN** the aggregate SHALL reject the command with a membership-domain error and emit no event

### Requirement: Invitation acceptance
The system SHALL require that an invitation is explicitly accepted via an `AcceptInvitation` command before the invitee becomes an active member; `InvitationAccepted` SHALL grant membership with the proposed role.

#### Scenario: Accepting a pending invitation
- **WHEN** an `AcceptInvitation { project_id, user_id }` command matches a pending invitation for that `user_id`
- **THEN** the aggregate SHALL emit `InvitationAccepted { project_id, user_id, role }` and SHALL record the user as an active member with that role

#### Scenario: Accepting without a pending invitation is rejected
- **WHEN** an `AcceptInvitation` command targets a `user_id` with no pending invitation
- **THEN** the aggregate SHALL reject the command with a membership-domain error and emit no event

### Requirement: Role granting
The system SHALL allow changing an existing active member's role via a `GrantRole` command, emitting a `RoleGranted` event that records the new role, replacing the prior role.

#### Scenario: Changing a member's role
- **WHEN** a `GrantRole { project_id, user_id, role }` command targets an active member
- **THEN** the aggregate SHALL emit `RoleGranted { project_id, user_id, role }` and SHALL replace the member's prior role with the new one

#### Scenario: Granting a role to a non-member is rejected
- **WHEN** a `GrantRole` command targets a `user_id` that is not an active member
- **THEN** the aggregate SHALL reject the command with a membership-domain error and emit no event

### Requirement: Member removal
The system SHALL allow removing an active member via a `RemoveMember` command, emitting a `MemberRemoved` event; a removed member SHALL no longer be an active member.

#### Scenario: Removing an active member
- **WHEN** a `RemoveMember { project_id, user_id }` command targets an active member
- **THEN** the aggregate SHALL emit `MemberRemoved { project_id, user_id }` and SHALL no longer consider that `user_id` an active member

### Requirement: Self-service leave
The system SHALL allow a member to leave a project via a `LeaveProject` command, equivalent in effect to `RemoveMember` but issued by the member themselves.

#### Scenario: A member leaves their project
- **WHEN** a `LeaveProject { project_id }` command is dispatched by an active member of that project
- **THEN** the aggregate SHALL emit `MemberRemoved { project_id, user_id }` for that member and SHALL no longer consider them an active member

### Requirement: Roles are production-scoped domain values
Roles SHALL be modeled as a domain `Role` enum local to the membership Bounded Context. A user's role SHALL be scoped to a single `ProjectId` and SHALL NOT be a global attribute of the user; the same `UserId` MAY hold different roles in different projects, including concurrently.

#### Scenario: Same user holds different roles across projects
- **WHEN** a `UserId` is an active member of two distinct `ProjectId`s
- **THEN** the system MAY record a different `Role` for that user in each project, and a role change in one project SHALL NOT affect the other

### Requirement: Initial role set
The initial role set SHALL consist of `Kostümbildner` and `Garderobier` as additive `Role` enum variants. The role set SHALL be designed for purely additive extension; removing or renaming a role SHALL be a breaking change requiring a separate proposal.

#### Scenario: The initial roles are available
- **WHEN** the membership Bounded Context is initialized
- **THEN** the `Role` enum SHALL include at minimum the variants `Kostümbildner` and `Garderobier`

### Requirement: Membership read model
The system SHALL maintain a membership projection in Postgres, updated by a membership projector reacting to membership events, exposing a query for "is `UserId` a member of `ProjectId`, and with which `Role`?". The projector SHALL be idempotent under event redelivery.

#### Scenario: Querying a member's role
- **WHEN** a query requests the role of `UserId` in `ProjectId` after `InvitationAccepted` has been projected
- **THEN** the read model SHALL return the user's active `Role` for that project

#### Scenario: Idempotent projection under redelivery
- **WHEN** the same membership event is delivered to the projector more than once
- **THEN** the projection SHALL apply the event exactly once and the read model SHALL reflect a single correct state

### Requirement: Membership does not own project lifecycle
The membership Bounded Context SHALL NOT model project metadata (name, dates, status, archival). It SHALL reference `ProjectId` only as an opaque identifier, consistent with the existing `scene`/`character`/`costume`/`calculation` contexts.

#### Scenario: Project metadata is out of scope
- **WHEN** a `ProjectMembership` aggregate is created
- **THEN** its state SHALL contain only the membership map keyed by `UserId` and SHALL NOT store any project-level metadata
