// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Errors of the project-scoped membership aggregate.

use thiserror::Error;

use crate::membership::Role;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ProjectMembershipError {
    /// Only the costume-department roles may be granted at project scope. The
    /// allowlist is enforced here, in the aggregate — never only at the edge.
    #[error("role {0:?} cannot be granted at project scope (costume-department roles only)")]
    NonCostumeRole(Role),
}
