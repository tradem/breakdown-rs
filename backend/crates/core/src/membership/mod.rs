// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block-scoped membership Bounded Context.
//!
//! Models membership and roles per `BlockId` (Decision 3). The aggregate
//! `BlockMembership` is event-sourced via `kameo_es` and owns only the
//! membership map — never block metadata (see `block-membership` spec).

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod policy;
pub mod ports;
pub mod views;

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

pub use aggregate::{BlockMembership, MembershipMetadata};
pub use commands::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, RemoveMember,
};
pub use error::MembershipError;
pub use events::MembershipEvent;
pub use ports::{MembershipCommands, MembershipRepository};
pub use views::{MembershipStateKind, MembershipView};

/// Block-scoped costume-department role.
///
/// Roles are **domain-local** and **block-scoped** (Decision 4): the same
/// `UserId` may hold a different `Role` in two blocks of the same season
/// because staff rotate roles at Block boundaries. The initial v1 set is
/// `CostumeDesigner` + `WardrobeSupervisor`, plus `CostumeAssistant` which is
/// the default role assigned to the block creator during the owner bootstrap
/// (see `BootstrapOwner`).
///
/// **Ubiquitous Language is English.** The enum variants and their `snake_case`
/// serde form are the canonical domain vocabulary, so events and projection
/// rows are persisted as English strings (`"costume_designer"`,
/// `"wardrobe_supervisor"`, `"costume_assistant"`).
///
/// The enum is **open for additive extension** (see `block-membership` spec,
/// "Initial role set"): adding a new variant is a non-breaking change for
/// writers, but renaming or removing an existing variant is a breaking change
/// requiring a separate proposal. Variants are serialized by their stable
/// `snake_case` name, so events/rows written today stay readable after a
/// future addition.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    /// Costume designer (Kostümbildner*in*).
    CostumeDesigner,
    /// Wardrobe supervisor (Garderobier*in*).
    WardrobeSupervisor,
    /// Costume assistant (Kostümassistent*in*) — default role for the block
    /// creator owner bootstrap (see `BootstrapOwner` / Decision A).
    CostumeAssistant,
}
