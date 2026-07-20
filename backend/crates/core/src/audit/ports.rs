// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Read port for the audit / journal projection.

use crate::audit::views::AuditEntry;
use crate::error::DomainError;
use crate::shared::{BlockId, UserId};
use async_trait::async_trait;
use chrono::{DateTime, Utc};

/// Async read port for the audit / journal projection.
///
/// Generic over the audit entry; the v1 implementation scopes queries to the
/// `membership` entity type. Methods are intentionally generic (by block, by
/// actor, by time range, by arbitrary entity) so future contexts reuse the
/// same projection without changing the port (decision 9.3).
#[async_trait]
pub trait AuditRepository: Send + Sync {
    /// Journal entries for a block, newest first.
    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError>;

    /// Journal entries acted on by a `UserId`, newest first.
    async fn list_by_actor(
        &self,
        actor: UserId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError>;

    /// Journal entries within a time range, newest first.
    async fn list_by_time_range(
        &self,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError>;

    /// Journal entries for an arbitrary `(entity_type, entity_id)` pair — the
    /// extension point for non-membership contexts.
    async fn list_by_entity(
        &self,
        entity_type: &str,
        entity_id: &str,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError>;
}
