// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::error::DomainError;
use sqlx::{PgPool, Postgres, Transaction};

/// PostgreSQL-backed global and per-user concurrency counter.
///
/// Acquisition and counter updates happen in one transaction, so a failed
/// per-user acquisition rolls back the global increment atomically.
#[derive(Clone, Debug)]
pub struct PgAiConcurrencyLimiter {
    pool: PgPool,
    max_global: i32,
    max_per_user: i32,
}

impl PgAiConcurrencyLimiter {
    pub fn new(pool: PgPool, max_global: u32, max_per_user: u32) -> Result<Self, DomainError> {
        let max_global = i32::try_from(max_global).map_err(|error| {
            DomainError::ValidationError(format!("global AI concurrency is too large: {error}"))
        })?;
        let max_per_user = i32::try_from(max_per_user).map_err(|error| {
            DomainError::ValidationError(format!("per-user AI concurrency is too large: {error}"))
        })?;
        if max_global <= 0 || max_per_user <= 0 || max_per_user > max_global {
            return Err(DomainError::ValidationError(
                "invalid AI concurrency limits".to_owned(),
            ));
        }
        Ok(Self {
            pool,
            max_global,
            max_per_user,
        })
    }

    pub async fn try_acquire(
        &self,
        user_id: &str,
    ) -> Result<Option<PgAiConcurrencyPermit>, DomainError> {
        if user_id.trim().is_empty() {
            return Err(DomainError::ValidationError(
                "AI concurrency user id must not be empty".to_owned(),
            ));
        }
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;
        let global = increment_counter(&mut tx, "global", "", self.max_global).await?;
        if global.is_none() {
            return Ok(None);
        }
        let user = increment_counter(&mut tx, "user", user_id, self.max_per_user).await?;
        if user.is_none() {
            return Ok(None);
        }
        tx.commit().await.map_err(map_sqlx_error)?;
        Ok(Some(PgAiConcurrencyPermit {
            pool: self.pool.clone(),
            user_id: user_id.to_owned(),
        }))
    }
}

pub struct PgAiConcurrencyPermit {
    pool: PgPool,
    user_id: String,
}

impl PgAiConcurrencyPermit {
    /// Release both the per-user and global counters. Call this after the job
    /// reaches a terminal queue state.
    pub async fn release(self) -> Result<(), DomainError> {
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;
        decrement_counter(&mut tx, "user", &self.user_id).await?;
        decrement_counter(&mut tx, "global", "").await?;
        tx.commit().await.map_err(map_sqlx_error)
    }
}

async fn increment_counter(
    tx: &mut Transaction<'_, Postgres>,
    scope: &str,
    user_id: &str,
    limit: i32,
) -> Result<Option<i32>, DomainError> {
    sqlx::query_scalar(
        r#"
        INSERT INTO ai_import.concurrency_counter (scope, user_id, in_flight)
        VALUES ($1, $2, 1)
        ON CONFLICT (scope, user_id) DO UPDATE
        SET in_flight = ai_import.concurrency_counter.in_flight + 1
        WHERE ai_import.concurrency_counter.in_flight < $3
        RETURNING in_flight
        "#,
    )
    .bind(scope)
    .bind(user_id)
    .bind(limit)
    .fetch_optional(&mut **tx)
    .await
    .map_err(map_sqlx_error)
}

async fn decrement_counter(
    tx: &mut Transaction<'_, Postgres>,
    scope: &str,
    user_id: &str,
) -> Result<(), DomainError> {
    sqlx::query(
        r#"
        UPDATE ai_import.concurrency_counter
        SET in_flight = GREATEST(in_flight - 1, 0)
        WHERE scope = $1 AND user_id = $2
        "#,
    )
    .bind(scope)
    .bind(user_id)
    .execute(&mut **tx)
    .await
    .map_err(map_sqlx_error)?;
    Ok(())
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::ServiceUnavailable(format!("AI concurrency database error: {error}"))
}
