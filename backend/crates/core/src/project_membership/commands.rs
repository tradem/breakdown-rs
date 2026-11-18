// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Commands of the project-scoped membership aggregate.

use kameo_es::CommandName;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::membership::Role;
use crate::shared::{ProjectId, UserId};

/// Bootstrap the season creator's project-scoped costume role.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct BootstrapProjectOwner {
    pub project_id: ProjectId,
    pub user_id: UserId,
}

impl CommandName for BootstrapProjectOwner {
    fn command_name() -> &'static str {
        "bootstrap_project_owner"
    }
}

/// Grant a costume role at project scope.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct GrantProjectRole {
    pub project_id: ProjectId,
    pub user_id: UserId,
    pub role: Role,
}

impl CommandName for GrantProjectRole {
    fn command_name() -> &'static str {
        "grant_project_role"
    }
}

/// Revoke a project-scoped grant.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RevokeProjectRole {
    pub project_id: ProjectId,
    pub user_id: UserId,
}

impl CommandName for RevokeProjectRole {
    fn command_name() -> &'static str {
        "revoke_project_role"
    }
}
