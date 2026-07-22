// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! BlockMembership aggregate using `kameo_es` event-sourced actor pattern.

use std::collections::HashMap;

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::BlockId;

use super::commands::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, RemoveMember,
};
use super::error::MembershipError;
use super::events::MembershipEvent;

/// Audit/actor metadata attached to every membership command (Decision 6).
///
/// The `actor` is the authenticated `UserId` performing the command. It is
/// persisted by `kameo_es` alongside the event for an audit trail, without
/// polluting command payloads. For `LeaveBlock` the `actor` *is* the member
/// being removed.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MembershipMetadata {
    pub actor: Option<crate::shared::UserId>,
}

/// Per-user membership state within a block.
///
/// Distinguishes a *pending* invitation (not yet an active member) from an
/// *active* member with a role.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MembershipState {
    Pending { role: super::Role },
    Active { role: super::Role },
}

/// State persisted by the `BlockMembership` aggregate.
///
/// One stream per `BlockId`. Holds only the membership map — never block
/// metadata (see `block-membership` spec, "Membership does not own block
/// lifecycle").
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BlockMembership {
    pub block_id: BlockId,
    pub members: HashMap<crate::shared::UserId, MembershipState>,
}

impl Entity for BlockMembership {
    type ID = Uuid;
    type Event = MembershipEvent;
    type Metadata = MembershipMetadata;

    fn category() -> &'static str {
        "membership"
    }
}

// ADR-002 (Event Sourcing / CQRS): apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
// `apply` MUST be idempotent: the projector redelivers events, so re-applying
// the same event leaves state unchanged (insert/remove are naturally
// idempotent; role replacement only touches an existing active member).
impl Apply for BlockMembership {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<Self::Metadata>) {
        match event {
            MembershipEvent::MemberInvited {
                block_id,
                user_id,
                role,
            } => {
                self.block_id = block_id;
                self.members
                    .insert(user_id, MembershipState::Pending { role });
            }
            MembershipEvent::InvitationAccepted {
                block_id,
                user_id,
                role,
            } => {
                self.block_id = block_id;
                self.members
                    .insert(user_id, MembershipState::Active { role });
            }
            MembershipEvent::RoleGranted {
                block_id,
                user_id,
                role,
            } => {
                self.block_id = block_id;
                if let Some(MembershipState::Active { role: r }) = self.members.get_mut(&user_id) {
                    *r = role;
                }
            }
            MembershipEvent::MemberRemoved { block_id, user_id } => {
                self.block_id = block_id;
                self.members.remove(&user_id);
            }
            MembershipEvent::OwnerBootstrapped {
                block_id,
                user_id,
                role,
            } => {
                self.block_id = block_id;
                self.members
                    .insert(user_id, MembershipState::Active { role });
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via `apply`.
impl Command<InviteMember> for BlockMembership {
    type Error = MembershipError;
    fn handle(
        &self,
        cmd: InviteMember,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.members.contains_key(&cmd.user_id) {
            return Err(MembershipError::AlreadyInvited {
                user_id: cmd.user_id,
            });
        }
        Ok(vec![MembershipEvent::MemberInvited {
            block_id: cmd.block_id,
            user_id: cmd.user_id,
            role: cmd.role,
        }])
    }
}

impl Command<AcceptInvitation> for BlockMembership {
    type Error = MembershipError;
    fn handle(
        &self,
        cmd: AcceptInvitation,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        let role = match self.members.get(&cmd.user_id) {
            Some(MembershipState::Pending { role }) => *role,
            _ => {
                return Err(MembershipError::NoPendingInvitation {
                    user_id: cmd.user_id,
                });
            }
        };
        Ok(vec![MembershipEvent::InvitationAccepted {
            block_id: cmd.block_id,
            user_id: cmd.user_id,
            role,
        }])
    }
}

impl Command<GrantRole> for BlockMembership {
    type Error = MembershipError;
    fn handle(
        &self,
        cmd: GrantRole,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        match self.members.get(&cmd.user_id) {
            Some(MembershipState::Active { .. }) => Ok(vec![MembershipEvent::RoleGranted {
                block_id: cmd.block_id,
                user_id: cmd.user_id,
                role: cmd.role,
            }]),
            _ => Err(MembershipError::NotActiveMember {
                user_id: cmd.user_id,
            }),
        }
    }
}

impl Command<RemoveMember> for BlockMembership {
    type Error = MembershipError;
    fn handle(
        &self,
        cmd: RemoveMember,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        match self.members.get(&cmd.user_id) {
            Some(MembershipState::Active { .. }) => Ok(vec![MembershipEvent::MemberRemoved {
                block_id: cmd.block_id,
                user_id: cmd.user_id,
            }]),
            _ => Err(MembershipError::NotActiveMember {
                user_id: cmd.user_id,
            }),
        }
    }
}

impl Command<LeaveBlock> for BlockMembership {
    type Error = MembershipError;
    fn handle(
        &self,
        cmd: LeaveBlock,
        ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // The leaving member is the authenticated actor (Decision 6): it is
        // carried in command metadata, not in the payload.
        let actor = ctx.metadata.data.as_ref().and_then(|m| m.actor.clone());
        let user_id = actor.ok_or(MembershipError::MissingActor)?;
        match self.members.get(&user_id) {
            Some(MembershipState::Active { .. }) => Ok(vec![MembershipEvent::MemberRemoved {
                block_id: cmd.block_id,
                user_id,
            }]),
            _ => Err(MembershipError::NotActiveMember { user_id }),
        }
    }
}

impl Command<BootstrapOwner> for BlockMembership {
    type Error = MembershipError;
    fn handle(
        &self,
        cmd: BootstrapOwner,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Bootstrap is only allowed on an empty block: once any member exists
        // the chicken-and-egg is already broken and ownership must change via
        // the normal invite/accept/grant flow, not by re-bootstrapping.
        if !self.members.is_empty() {
            return Err(MembershipError::BootstrapNotAllowed { id: cmd.block_id });
        }
        Ok(vec![MembershipEvent::OwnerBootstrapped {
            block_id: cmd.block_id,
            user_id: cmd.user_id,
            role: cmd.role,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
