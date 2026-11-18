// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Events of the project-scoped membership aggregate.

use kameo_es::EventType;
use serde::{Deserialize, Serialize};

use crate::membership::Role;
use crate::shared::{ProjectId, UserId};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ProjectMembershipEvent {
    /// The season creator's bootstrap grant (the project-scope mirror of the
    /// block-scope `OwnerBootstrapped`).
    ProjectOwnerBootstrapped {
        project_id: ProjectId,
        user_id: UserId,
        role: Role,
    },
    /// An explicit project-scoped costume role grant.
    ProjectRoleGranted {
        project_id: ProjectId,
        user_id: UserId,
        role: Role,
    },
    /// Removal of a project-scoped grant.
    ProjectRoleRevoked {
        project_id: ProjectId,
        user_id: UserId,
    },
}

impl EventType for ProjectMembershipEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::ProjectOwnerBootstrapped { .. } => "project_owner_bootstrapped",
            Self::ProjectRoleGranted { .. } => "project_role_granted",
            Self::ProjectRoleRevoked { .. } => "project_role_revoked",
        }
    }
}
