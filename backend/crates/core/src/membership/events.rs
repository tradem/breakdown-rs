// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Membership domain events.

use crate::shared::{BlockId, UserId};
use kameo_es::EventType;
use serde::{Deserialize, Serialize};

use crate::membership::Role;

/// Events emitted by the `BlockMembership` aggregate.
///
/// Events never carry the acting `UserId`; audit of *who emitted* an event is
/// stored in the command `Metadata` (Decision 6), not in the event payload.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum MembershipEvent {
    /// A `user_id` was invited to the block with a proposed `role`. The invitee
    /// is *not yet* an active member until they `AcceptInvitation`.
    MemberInvited {
        block_id: BlockId,
        user_id: UserId,
        role: Role,
    },
    /// The invitee accepted; they become an active member with `role`.
    InvitationAccepted {
        block_id: BlockId,
        user_id: UserId,
        role: Role,
    },
    /// An active member's role was changed (prior role replaced).
    RoleGranted {
        block_id: BlockId,
        user_id: UserId,
        role: Role,
    },
    /// A member (active) was removed; they are no longer part of the block.
    MemberRemoved { block_id: BlockId, user_id: UserId },
    /// The block's first (owner) member was bootstrapped. Emitted by
    /// `BootstrapOwner` and applied exactly like an accepted invitation: the
    /// user becomes an active member with `role`. This is the only path that
    /// can seed the first active member of a block (Decision A).
    OwnerBootstrapped {
        block_id: BlockId,
        user_id: UserId,
        role: Role,
    },
}

impl EventType for MembershipEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::MemberInvited { .. } => "MemberInvited",
            Self::InvitationAccepted { .. } => "InvitationAccepted",
            Self::RoleGranted { .. } => "RoleGranted",
            Self::MemberRemoved { .. } => "MemberRemoved",
            Self::OwnerBootstrapped { .. } => "OwnerBootstrapped",
        }
    }
}
