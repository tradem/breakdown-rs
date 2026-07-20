// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! PostgreSQL read adapter for the audit / journal projection.

use async_trait::async_trait;
use breakdown_core::audit::ports::AuditRepository;
use breakdown_core::audit::views::AuditEntry;
use breakdown_core::error::DomainError;
use breakdown_core::shared::{BlockId, UserId};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// PostgreSQL read adapter for audit projections.
#[derive(Clone, Debug)]
pub struct AuditRepositoryImpl {
    pool: PgPool,
}

impl AuditRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl AuditRepository for AuditRepositoryImpl {
    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        let rows = sqlx::query("SELECT id, entity_type, entity_id, event_type, block_id, series_id, actor, payload, occurred_at FROM projection_audit WHERE block_id = $1 ORDER BY occurred_at DESC, id DESC LIMIT $2 OFFSET $3")
        .bind(block_id.0)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_audit_row).collect()
    }

    async fn list_by_actor(
        &self,
        actor: UserId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        let rows = sqlx::query("SELECT id, entity_type, entity_id, event_type, block_id, series_id, actor, payload, occurred_at FROM projection_audit WHERE actor = $1 ORDER BY occurred_at DESC, id DESC LIMIT $2 OFFSET $3")
        .bind(actor.as_str())
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_audit_row).collect()
    }

    async fn list_by_time_range(
        &self,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        let rows = sqlx::query("SELECT id, entity_type, entity_id, event_type, block_id, series_id, actor, payload, occurred_at FROM projection_audit WHERE occurred_at BETWEEN $1 AND $2 ORDER BY occurred_at DESC, id DESC LIMIT $3 OFFSET $4")
        .bind(from)
        .bind(to)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_audit_row).collect()
    }

    async fn list_by_entity(
        &self,
        entity_type: &str,
        entity_id: &str,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        let rows = sqlx::query("SELECT id, entity_type, entity_id, event_type, block_id, series_id, actor, payload, occurred_at FROM projection_audit WHERE entity_type = $1 AND entity_id = $2 ORDER BY occurred_at DESC, id DESC LIMIT $3 OFFSET $4")
        .bind(entity_type)
        .bind(entity_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

        rows.into_iter().map(map_audit_row).collect()
    }
}

fn map_audit_row(row: sqlx::postgres::PgRow) -> Result<AuditEntry, DomainError> {
    let id: Uuid = row
        .try_get("id")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let entity_type: String = row
        .try_get("entity_type")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let entity_id: String = row
        .try_get("entity_id")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let event_type: String = row
        .try_get("event_type")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let block_id: Option<BlockId> = row
        .try_get::<Option<Uuid>, _>("block_id")
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .map(BlockId::from_uuid);
    let series_id: Option<Uuid> = row
        .try_get("series_id")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let actor: Option<UserId> = row
        .try_get::<Option<String>, _>("actor")
        .map_err(|e| DomainError::Conflict(e.to_string()))?
        .map(UserId::from_sub);
    let payload: serde_json::Value = row
        .try_get("payload")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;
    let occurred_at: DateTime<Utc> = row
        .try_get("occurred_at")
        .map_err(|e| DomainError::Conflict(e.to_string()))?;

    Ok(AuditEntry {
        id,
        entity_type,
        entity_id,
        event_type,
        block_id,
        series_id,
        actor,
        payload,
        occurred_at,
    })
}
