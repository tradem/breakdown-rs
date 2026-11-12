// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: hy4-preview (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `sqlx`-backed implementation of the `MembershipRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::membership::Role;
use breakdown_core::membership::ports::MembershipRepository;
use breakdown_core::membership::views::{MembershipStateKind, MembershipView};
use breakdown_core::shared::{BlockId, ProjectId, SeasonId, UserId};
use sqlx::{PgPool, Row};

use async_trait::async_trait;

/// PostgreSQL read adapter for membership projections.
#[derive(Clone, Debug)]
pub struct MembershipRepositoryImpl {
    pool: PgPool,
}

impl MembershipRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl MembershipRepository for MembershipRepositoryImpl {
    async fn find(
        &self,
        block_id: BlockId,
        user_id: UserId,
    ) -> Result<Option<MembershipView>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT block_id, user_id, role, state, joined_at
            FROM projection_membership
            WHERE block_id = $1 AND user_id = $2
            LIMIT 1
            "#,
        )
        .bind(block_id.0)
        .bind(user_id.as_str())
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        match row {
            Some(row) => Ok(Some(map_membership_row(row)?)),
            None => Ok(None),
        }
    }

    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<MembershipView>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT block_id, user_id, role, state, joined_at
            FROM projection_membership
            WHERE block_id = $1
            ORDER BY user_id
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(block_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        rows.into_iter().map(map_membership_row).collect()
    }

    async fn is_active_member(
        &self,
        block_id: BlockId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        Ok(self
            .find(block_id, user_id)
            .await?
            .is_some_and(|m| matches!(m.state, MembershipStateKind::Active)))
    }

    async fn has_active_membership_in_project(
        &self,
        project_id: ProjectId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        // Tenant scope is resolved along the production hierarchy
        // (membership -> block -> season -> project). `projection_block`
        // carries the project as a denormalized, indexed column written from
        // the very same event as `season_id`, so the block join answers the
        // question directly. Role-agnostic: any active membership in any
        // block of the project grants access (issue #342).
        let row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT m.role
            FROM projection_membership m
            JOIN projection_block b ON b.id = m.block_id
            WHERE m.user_id = $1
              AND b.project_id = $2
              AND m.state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .bind(project_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(row.is_some())
    }

    async fn has_active_costume_role_in_project(
        &self,
        project_id: ProjectId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        let row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT m.role
            FROM projection_membership m
            JOIN projection_block b ON b.id = m.block_id
            WHERE m.user_id = $1
              AND b.project_id = $2
              AND m.role IN ('costume_designer', 'wardrobe_supervisor', 'costume_assistant')
              AND m.state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .bind(project_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(row.is_some())
    }

    async fn has_active_costume_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        let row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT m.role
            FROM projection_membership m
            JOIN projection_block b ON b.id = m.block_id
            WHERE m.user_id = $1
              AND b.season_id = $2
              AND m.role IN ('costume_designer', 'wardrobe_supervisor', 'costume_assistant')
              AND m.state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .bind(season_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(row.is_some())
    }

    async fn effective_costume_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<Option<Role>, DomainError> {
        // Scope 1 — block membership in the season (the pre-existing
        // resolution, unchanged). Two statements instead of a UNION on purpose:
        // the block scope stays exactly the query it always was, and the
        // project scope is only paid for when the block scope misses.
        let block_row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT m.role
            FROM projection_membership m
            JOIN projection_block b ON b.id = m.block_id
            WHERE m.user_id = $1
              AND b.season_id = $2
              AND m.role IN ('costume_designer', 'wardrobe_supervisor', 'costume_assistant')
              AND m.state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .bind(season_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        if let Some((token,)) = block_row {
            // The token already passed the SQL allowlist; `Role::from_token`
            // only guards against a hand-edited row, and an unparsable token is
            // treated as "no role" (fail closed).
            return Ok(Role::from_token(&token));
        }

        // Scope 2 — a project-scoped grant on the project this season belongs
        // to. The `projection_season` join is what makes an unresolvable
        // season fail CLOSED: no projected season row ⇒ no project ⇒ no match,
        // so a season the read model does not know can never authorize.
        let project_row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT pm.role
            FROM projection_project_membership pm
            JOIN projection_season s ON s.id = $2 AND s.project_id = pm.project_id
            WHERE pm.user_id = $1
              AND pm.role IN ('costume_designer', 'wardrobe_supervisor', 'costume_assistant')
              AND pm.state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .bind(season_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(project_row.and_then(|(token,)| Role::from_token(&token)))
    }

    async fn has_active_report_archive_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        // Static role allowlist — CostumeDesigner + WardrobeSupervisor only.
        // CostumeAssistant is deliberately excluded (manual archive remediation).
        let row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT m.role
            FROM projection_membership m
            JOIN projection_block b ON b.id = m.block_id
            WHERE m.user_id = $1
              AND b.season_id = $2
              AND m.role IN ('costume_designer', 'wardrobe_supervisor')
              AND m.state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .bind(season_id.0)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| DomainError::internal(e.to_string()))?;

        Ok(row.is_some())
    }

    async fn has_active_credential_role(&self, user_id: UserId) -> Result<bool, DomainError> {
        let row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT role
            FROM projection_membership
            WHERE user_id = $1
              AND role IN ('costume_designer', 'costume_assistant')
              AND state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .fetch_optional(&self.pool)
        .await
        .map_err(|err| DomainError::internal(err.to_string()))?;
        Ok(row.is_some())
    }

    async fn has_active_ops_role(&self, user_id: UserId) -> Result<bool, DomainError> {
        // Deployment-scoped ops capability (issue #409): any active
        // `ops_admin` membership in any block grants access — the projection
        // column stores the plain token (`Role::as_str`), see
        // `crates/core/tests/membership_projection_tokens.rs`.
        let row: Option<(String,)> = sqlx::query_as(
            r#"
            SELECT role
            FROM projection_membership
            WHERE user_id = $1
              AND role = 'ops_admin'
              AND state = 'active'
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .fetch_optional(&self.pool)
        .await
        .map_err(|err| DomainError::internal(err.to_string()))?;
        Ok(row.is_some())
    }
}

fn map_membership_row(row: sqlx::postgres::PgRow) -> Result<MembershipView, DomainError> {
    let role_str: String = row
        .try_get("role")
        .map_err(|e| DomainError::internal(e.to_string()))?;
    let state_str: String = row
        .try_get("state")
        .map_err(|e| DomainError::internal(e.to_string()))?;

    // The columns hold plain tokens (`costume_assistant`, `active`) — see the
    // module docs of `crates/infra/src/projectors/membership.rs`. Rows written
    // by an older projector carry the JSON form and are rejected loudly rather
    // than silently mis-read. Deliberately no legacy tolerance and no data
    // migration: the backend is pre-production, so dev databases are re-seeded
    // (issue #342, `crates/infra/CHANGELOG.md` §0.15.0).
    let role = Role::from_token(&role_str)
        .ok_or_else(|| DomainError::internal(format!("invalid role in projection: {role_str}")))?;
    let state = MembershipStateKind::from_token(&state_str).ok_or_else(|| {
        DomainError::internal(format!("invalid state in projection: {state_str}"))
    })?;

    Ok(MembershipView {
        block_id: BlockId(
            row.try_get("block_id")
                .map_err(|e| DomainError::internal(e.to_string()))?,
        ),
        user_id: UserId::from_sub(
            row.try_get::<String, _>("user_id")
                .map_err(|e| DomainError::internal(e.to_string()))?,
        ),
        role,
        state,
        joined_at: row
            .try_get("joined_at")
            .map_err(|e| DomainError::internal(e.to_string()))?,
    })
}
