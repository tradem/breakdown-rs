// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `sqlx`-backed implementation of the `MembershipRepository` port.

use breakdown_core::error::DomainError;
use breakdown_core::membership::ports::MembershipRepository;
use breakdown_core::membership::views::{MembershipStateKind, MembershipView};
use breakdown_core::shared::{BlockId, SeasonId, UserId};
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
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

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
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

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
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        Ok(row.is_some())
    }
}

fn map_membership_row(row: sqlx::postgres::PgRow) -> Result<MembershipView, DomainError> {
    let role_str: String = row
        .try_get("role")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let state_str: String = row
        .try_get("state")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

    let role = serde_json::from_str(&role_str)
        .map_err(|e| DomainError::Conflict(format!("invalid role in projection: {e}")))?;
    let state = serde_json::from_str(&state_str)
        .map_err(|e| DomainError::Conflict(format!("invalid state in projection: {e}")))?;

    Ok(MembershipView {
        block_id: BlockId(
            row.try_get("block_id")
                .map_err(|e| DomainError::Conflict(e.to_string()))?,
        ),
        user_id: UserId::from_sub(
            row.try_get::<String, _>("user_id")
                .map_err(|e| DomainError::Conflict(e.to_string()))?,
        ),
        role,
        state,
        joined_at: row
            .try_get("joined_at")
            .map_err(|e| DomainError::Conflict(e.to_string()))?,
    })
}
