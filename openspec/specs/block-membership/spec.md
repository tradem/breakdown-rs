# block-membership Specification

## Purpose
TBD - created by archiving change add-oidc-auth-and-membership. Update Purpose after archive.
## Requirements
### Requirement: Block Membership aggregate
The system SHALL model block-scoped membership as a `BlockMembership` aggregate, event-sourced via `kameo_es`, scoped per `BlockId` and holding a map of `UserId -> Role`. A membership aggregate SHALL belong to exactly one `BlockId`. This requirement depends on the `Block` aggregate and `BlockId` value type introduced by the `introduce-season-block-episode-hierarchy` change, which SHALL land first.

#### Scenario: Aggregate is keyed by block
- **WHEN** a `BlockMembership` aggregate is instantiated
- **THEN** its identity SHALL consist of a single `BlockId`, and it SHALL reference members only relative to that block

### Requirement: Member invitation
The system SHALL allow inviting a `UserId` to a block via an `InviteMember` command, emitting a `MemberInvited` event recording the invitee and proposed role, without granting membership until the invitation is accepted.

#### Scenario: Inviting a new member
- **WHEN** an `InviteMember { block_id, user_id, role }` command is dispatched and the `user_id` is not yet a member
- **THEN** the aggregate SHALL emit `MemberInvited { block_id, user_id, role }` and SHALL NOT yet consider the user an active member

#### Scenario: Re-inviting an existing invitee is rejected
- **WHEN** an `InviteMember` command targets a `user_id` that already has a pending invitation
- **THEN** the aggregate SHALL reject the command with a membership-domain error and emit no event

### Requirement: Invitation acceptance
The system SHALL require that an invitation is explicitly accepted via an `AcceptInvitation` command before the invitee becomes an active member; `InvitationAccepted` SHALL grant membership with the proposed role.

#### Scenario: Accepting a pending invitation
- **WHEN** an `AcceptInvitation { block_id, user_id }` command matches a pending invitation for that `user_id`
- **THEN** the aggregate SHALL emit `InvitationAccepted { block_id, user_id, role }` and SHALL record the user as an active member with that role

#### Scenario: Accepting without a pending invitation is rejected
- **WHEN** an `AcceptInvitation` command targets a `user_id` with no pending invitation
- **THEN** the aggregate SHALL reject the command with a membership-domain error and emit no event

### Requirement: Role granting
The system SHALL allow changing an existing active member's role via a `GrantRole` command, emitting a `RoleGranted` event that records the new role, replacing the prior role.

#### Scenario: Changing a member's role
- **WHEN** a `GrantRole { block_id, user_id, role }` command targets an active member
- **THEN** the aggregate SHALL emit `RoleGranted { block_id, user_id, role }` and SHALL replace the member's prior role with the new one

#### Scenario: Granting a role to a non-member is rejected
- **WHEN** a `GrantRole` command targets a `user_id` that is not an active member
- **THEN** the aggregate SHALL reject the command with a membership-domain error and emit no event

### Requirement: Member removal
The system SHALL allow removing an active member via a `RemoveMember` command, emitting a `MemberRemoved` event; a removed member SHALL no longer be an active member.

#### Scenario: Removing an active member
- **WHEN** a `RemoveMember { block_id, user_id }` command targets an active member
- **THEN** the aggregate SHALL emit `MemberRemoved { block_id, user_id }` and SHALL no longer consider that `user_id` an active member

### Requirement: Self-service leave
The system SHALL allow a member to leave a block via a `LeaveBlock` command, equivalent in effect to `RemoveMember` but issued by the member themselves.

#### Scenario: A member leaves their block
- **WHEN** a `LeaveBlock { block_id }` command is dispatched by an active member of that block
- **THEN** the aggregate SHALL emit `MemberRemoved { block_id, user_id }` for that member and SHALL no longer consider them an active member

### Requirement: Bootstrap owner (auto-owner on block creation)
The system SHALL let the user who creates a `Block` become its first
active member (owner) without a pre-existing membership, resolving the
seed/bootstrap chicken-and-egg gap. This is expressed as a dedicated
`BootstrapOwner` command emitting `OwnerBootstrapped`, with a default
role of `CostumeAssistant`. `BootstrapOwner` SHALL be rejected with a
membership-domain error (`BootstrapNotAllowed`) once the block already has
≥1 member, so it can never be used to add/overwrite members after seeding.

#### Scenario: Creator is bootstrapped as owner
- **WHEN** a `BootstrapOwner { block_id, user_id }` command targets a `BlockMembership` that has no members yet
- **THEN** the aggregate SHALL emit `OwnerBootstrapped { block_id, user_id, role: CostumeAssistant }` and SHALL consider `user_id` an active member with that role

#### Scenario: Bootstrap is rejected once seeded
- **WHEN** a `BootstrapOwner` command targets a block that already has ≥1 active member
- **THEN** the aggregate SHALL reject the command with `BootstrapNotAllowed` and emit no event

### Requirement: Roles are block-scoped domain values
Roles SHALL be modeled as a domain `Role` enum local to the membership Bounded Context. A user's role SHALL be scoped to a single `BlockId` and SHALL NOT be a global attribute of the user, nor even a season/series-scoped one. The same `UserId` MAY hold different roles in different blocks — including two blocks of the same season, concurrently — because costume-department staff rotate roles at block boundaries.

#### Scenario: Same user holds different roles across blocks of one season
- **WHEN** a `UserId` is an active member of Block 1 and Block 2 of the same season
- **THEN** the system MAY record a different `Role` for that user in each block (e.g. `costume_designer` in Block 1 and `wardrobe_supervisor` in Block 2), and a role change in one block SHALL NOT affect the other

### Requirement: Initial role set
The initial v1 role set SHALL consist of `CostumeDesigner` (`costume_designer`),
`WardrobeSupervisor` (`wardrobe_supervisor`), and `CostumeAssistant`
(`costume_assistant`) as additive `Role` enum variants (English ubiquitous-language
spelling, `#[serde(rename_all = "snake_case")]` on the wire). The role set SHALL
be designed for purely additive extension; removing or renaming a role SHALL be a
breaking change requiring a separate proposal.

#### Scenario: The initial roles are available
- **WHEN** the membership Bounded Context is initialized
- **THEN** the `Role` enum SHALL include the variants `CostumeDesigner`, `WardrobeSupervisor`, and `CostumeAssistant`

### Requirement: Membership read model
The system SHALL maintain a membership projection in Postgres, updated by a membership projector reacting to membership events, exposing a query for "is `UserId` a member of `BlockId`, and with which `Role`?". The projector SHALL be idempotent under event redelivery.

#### Scenario: Querying a member's role
- **WHEN** a query requests the role of `UserId` in `BlockId` after `InvitationAccepted` has been projected
- **THEN** the read model SHALL return the user's active `Role` for that block

#### Scenario: Idempotent projection under redelivery
- **WHEN** the same membership event is delivered to the projector more than once
- **THEN** the projection SHALL apply the event exactly once and the read model SHALL reflect a single correct state

### Requirement: Membership does not own block lifecycle
The membership Bounded Context SHALL NOT model block metadata (number, dates, parent season). It SHALL reference `BlockId` only as an opaque identifier, consistent with the existing `scene`/`character`/`costume` contexts' treatment of their parent IDs.

#### Scenario: Block metadata is out of scope
- **WHEN** a `BlockMembership` aggregate is created
- **THEN** its state SHALL contain only the membership map keyed by `UserId` and SHALL NOT store any block-level metadata

### Requirement: Membership audit journal (queryable projection)
The system SHALL maintain a queryable audit/journal projection recording membership-domain events (`MemberInvited`, `InvitationAccepted`, `RoleGranted`, `MemberRemoved`, `OwnerBootstrapped`), capturing the acting `sub` (from command metadata), the `block_id`, the event type, and the time of occurrence. The journal SHALL be idempotent under event redelivery (ADR-016). The projection schema SHALL be generic (`entity_type` + `payload` JSONB + nullable tenant/`series_id`) so that events from other Bounded Contexts can be appended in a future change without a breaking migration; the v1 scope is membership-only and SHALL NOT preclude a future all-domain journal.

#### Scenario: Membership change is recorded
- **WHEN** a `MembershipEvent` has been projected
- **THEN** the audit journal SHALL contain a row for that event with the acting `sub`, `block_id`, event type, and `occurred_at`

#### Scenario: Idempotent audit under redelivery
- **WHEN** the same membership event is delivered more than once
- **THEN** the audit journal SHALL contain exactly one row for that event

