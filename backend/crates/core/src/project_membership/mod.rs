// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Project-scoped costume-department membership.
//!
//! Block membership (`crate::membership`) grants a role **at a block** — the
//! scope that rotates at block boundaries. It cannot express a role for a
//! production that has no block yet, so a season without blocks was role-less
//! by construction and every season-scoped authorization check on it was
//! refused (see `openspec/changes/project-scoped-membership`).
//!
//! This module is the second, additive scope: one stream per **project**
//! (`project_membership-{project_id}`) holding the project's costume roles.
//! Effective authorization resolves block scope first, then this one
//! (`MembershipRepository::effective_costume_role_in_season`).

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;

pub use aggregate::{ProjectMembership, is_costume_role};
pub use commands::{BootstrapProjectOwner, GrantProjectRole, RevokeProjectRole};
pub use error::ProjectMembershipError;
pub use events::ProjectMembershipEvent;
