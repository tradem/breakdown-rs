// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `ProjectMembership` aggregate — one stream per project.

use std::collections::HashMap;

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::membership::Role;
use crate::shared::{EventMetadata, ProjectId, UserId};

use super::commands::{BootstrapProjectOwner, GrantProjectRole, RevokeProjectRole};
use super::error::ProjectMembershipError;
use super::events::ProjectMembershipEvent;

/// Roles a project-scoped grant may carry.
///
/// Deliberately the same costume-department allowlist the block-scoped season
/// predicate uses. `OpsAdmin` is deployment-scoped and must never be reachable
/// through a production grant.
#[must_use]
pub fn is_costume_role(role: Role) -> bool {
    matches!(
        role,
        Role::CostumeDesigner | Role::WardrobeSupervisor | Role::CostumeAssistant
    )
}

/// Project-scoped memberships of one project.
///
/// Holds only roles — never project metadata (the project has no aggregate of
/// its own yet; ADR-035 S1 keeps the opaque `ProjectId` seam).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ProjectMembership {
    pub project_id: ProjectId,
    /// Active grants. A revocation removes the entry; a re-grant overwrites it,
    /// so an active user always holds exactly one project-scoped role.
    pub members: HashMap<UserId, Role>,
}

impl ProjectMembership {
    /// The active project-scoped role of `user_id`, if any.
    #[must_use]
    pub fn role_of(&self, user_id: &UserId) -> Option<Role> {
        self.members.get(user_id).copied()
    }
}

impl Entity for ProjectMembership {
    type ID = Uuid;
    type Event = ProjectMembershipEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "project_membership"
    }
}

impl Apply for ProjectMembership {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            ProjectMembershipEvent::ProjectOwnerBootstrapped {
                project_id,
                user_id,
                role,
            }
            | ProjectMembershipEvent::ProjectRoleGranted {
                project_id,
                user_id,
                role,
            } => {
                self.project_id = project_id;
                self.members.insert(user_id, role);
            }
            ProjectMembershipEvent::ProjectRoleRevoked {
                project_id,
                user_id,
            } => {
                self.project_id = project_id;
                self.members.remove(&user_id);
            }
        }
    }
}

impl Command<BootstrapProjectOwner> for ProjectMembership {
    type Error = ProjectMembershipError;

    fn handle(
        &self,
        cmd: BootstrapProjectOwner,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // The bootstrap is the same shape as an explicit grant; a distinct
        // event keeps its origin visible in the audit trail.
        Ok(vec![ProjectMembershipEvent::ProjectOwnerBootstrapped {
            project_id: cmd.project_id,
            user_id: cmd.user_id,
            role: Role::CostumeDesigner,
        }])
    }

    /// A second season in the same project must not re-bootstrap: the state
    /// already carries the creator's role.
    fn is_state_idempotent(&self, cmd: &BootstrapProjectOwner, _ctx: Context<'_, Self>) -> bool {
        self.role_of(&cmd.user_id).is_some()
    }
}

impl Command<GrantProjectRole> for ProjectMembership {
    type Error = ProjectMembershipError;

    fn handle(
        &self,
        cmd: GrantProjectRole,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if !is_costume_role(cmd.role) {
            return Err(ProjectMembershipError::NonCostumeRole(cmd.role));
        }
        Ok(vec![ProjectMembershipEvent::ProjectRoleGranted {
            project_id: cmd.project_id,
            user_id: cmd.user_id,
            role: cmd.role,
        }])
    }

    /// Re-granting the role the user already holds is a no-op.
    fn is_state_idempotent(&self, cmd: &GrantProjectRole, _ctx: Context<'_, Self>) -> bool {
        self.role_of(&cmd.user_id) == Some(cmd.role)
    }
}

impl Command<RevokeProjectRole> for ProjectMembership {
    type Error = ProjectMembershipError;

    fn handle(
        &self,
        cmd: RevokeProjectRole,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![ProjectMembershipEvent::ProjectRoleRevoked {
            project_id: cmd.project_id,
            user_id: cmd.user_id,
        }])
    }

    /// Revoking a grant the user does not hold is a no-op.
    fn is_state_idempotent(&self, cmd: &RevokeProjectRole, _ctx: Context<'_, Self>) -> bool {
        self.role_of(&cmd.user_id).is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids() -> (ProjectId, UserId) {
        (ProjectId::new(), UserId("dev-user".into()))
    }

    fn apply(state: &mut ProjectMembership, event: ProjectMembershipEvent) {
        Apply::apply(state, event, Metadata::default());
    }

    #[test]
    fn apply_grants_and_revokes_idempotently() {
        let (project_id, user_id) = ids();
        let mut state = ProjectMembership::default();
        let grant = ProjectMembershipEvent::ProjectRoleGranted {
            project_id,
            user_id: user_id.clone(),
            role: Role::WardrobeSupervisor,
        };
        // A redelivered event must not duplicate the row.
        apply(&mut state, grant.clone());
        apply(&mut state, grant);
        assert_eq!(state.role_of(&user_id), Some(Role::WardrobeSupervisor));
        assert_eq!(state.members.len(), 1);
        assert_eq!(state.project_id, project_id);

        let revoke = ProjectMembershipEvent::ProjectRoleRevoked {
            project_id,
            user_id: user_id.clone(),
        };
        apply(&mut state, revoke.clone());
        apply(&mut state, revoke);
        assert!(state.members.is_empty(), "revoke twice stays empty");
    }

    #[test]
    fn bootstrap_grants_the_designer_role() {
        let (project_id, user_id) = ids();
        let mut state = ProjectMembership::default();
        apply(
            &mut state,
            ProjectMembershipEvent::ProjectOwnerBootstrapped {
                project_id,
                user_id: user_id.clone(),
                role: Role::CostumeDesigner,
            },
        );
        assert_eq!(state.role_of(&user_id), Some(Role::CostumeDesigner));
    }

    #[test]
    fn only_costume_roles_are_project_grantable() {
        assert!(is_costume_role(Role::CostumeDesigner));
        assert!(is_costume_role(Role::WardrobeSupervisor));
        assert!(is_costume_role(Role::CostumeAssistant));
        assert!(!is_costume_role(Role::OpsAdmin));
    }
}
