// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use std::collections::{HashMap, HashSet};
use std::sync::{PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};

use breakdown_core::ai::{
    AiImportJobId, AiImportMapping, AiImportMappingRepository, PRIMARY_ORDINAL,
};
use breakdown_core::error::DomainError;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Full primary key of one mapping row: `(preview, draft_ref, kind, ordinal)`.
type MappingKey = (AiImportJobId, String, String, i32);

/// Build the cache key of a mapping row from its parts.
fn mapping_key(
    preview_id: AiImportJobId,
    draft_ref: &str,
    aggregate_kind: &str,
    ordinal: i32,
) -> MappingKey {
    (
        preview_id,
        draft_ref.to_owned(),
        aggregate_kind.to_owned(),
        ordinal,
    )
}

/// What one apply run has learned about the mapping table.
#[derive(Debug, Default)]
struct MappingSnapshot {
    /// Known rows, keyed like the table. Only rows that exist; "absent" is
    /// decided by [`Self::complete`], never by a missing entry — a key nobody
    /// has read yet is *unknown*, and answering `None` for it would invent a
    /// reservation-free row.
    rows: HashMap<MappingKey, AiImportMapping>,
    /// Previews whose every row has been listed, so a key that is absent from
    /// [`Self::rows`] is known-not-to-exist.
    complete: HashSet<AiImportJobId>,
}

/// Read-through cache over [`AiImportMappingRepository`] for **one apply run**.
///
/// Why this exists (live-test finding): an apply is an idempotency-checked
/// write loop, and every aggregate it creates (`scene`, `episode`, `character`,
/// `piece`, `outfit`, `outfit beat`, `scene_shoot`) used to start with its own
/// `find` — one SQL round trip per aggregate, strictly sequential. For a
/// 57-scene script that is hundreds of trips that all answer the same question
/// about a table this run already lists once.
///
/// Semantics are the repository's, not a weaker version of them:
///
/// * a `find` is answered from memory only when the row is cached **or** its
///   preview was listed completely (a listed preview makes an absent key a
///   known `None`);
/// * `reserve` and `insert` always reach the store and mirror its answer — with
///   the same monotonic rule (`insert` only advances a row) the SQL enforces,
///   so a late duplicate can never roll the cache back either;
/// * `list_by_preview` primes the cache for that preview.
///
/// Correctness rests on the apply being **single-flight per preview**
/// (`AiImportQueue::claim_apply_run`): one run, one owner, one cache. A stolen
/// claim (the documented staleness takeover) can therefore see a stale `None`
/// and dispatch a create that the other run already committed — that is the
/// documented convergence path (`derive_id` + `ExpectedVersion::Empty` +
/// `created_now`), it costs one recovered append, never a duplicate aggregate.
#[derive(Debug)]
pub struct CachedMappings<M> {
    inner: M,
    snapshot: RwLock<MappingSnapshot>,
}

impl<M> CachedMappings<M> {
    /// Wrap `inner` in a fresh (empty) per-run cache.
    pub fn new(inner: M) -> Self {
        Self {
            inner,
            snapshot: RwLock::new(MappingSnapshot::default()),
        }
    }

    /// A poisoned lock carries a consistent snapshot: every writer mutates it
    /// under the same guard and no operation can leave a half-written row, so
    /// recovering the guard is safe and cannot panic a request (AGENTS.md §1).
    fn read(&self) -> RwLockReadGuard<'_, MappingSnapshot> {
        self.snapshot.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> RwLockWriteGuard<'_, MappingSnapshot> {
        self.snapshot
            .write()
            .unwrap_or_else(PoisonError::into_inner)
    }

    /// `Some(row)` when the cache knows the answer (`row` = `None` for a key
    /// proven absent), `None` when it has to ask the store.
    fn lookup(&self, key: &MappingKey) -> Option<Option<AiImportMapping>> {
        let snapshot = self.read();
        if let Some(row) = snapshot.rows.get(key) {
            return Some(Some(row.clone()));
        }
        snapshot.complete.contains(&key.0).then_some(None)
    }
}

#[derive(Clone, Debug)]
pub struct PgAiImportMappingRepository {
    pool: PgPool,
}

impl PgAiImportMappingRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl AiImportMappingRepository for PgAiImportMappingRepository {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
        aggregate_kind: &str,
        ordinal: i32,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version
            FROM ai_import.projection_ai_import_mapping
            WHERE preview_id = $1 AND draft_ref = $2
              AND aggregate_kind = $3 AND ordinal = $4
            "#,
        )
        .bind(preview_id.as_uuid())
        .bind(draft_ref)
        .bind(aggregate_kind)
        .bind(ordinal)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        row.map(map_mapping).transpose()
    }

    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError> {
        // Insert-if-absent on the full row key. A competing apply (or a retry
        // after a crashed confirm) gets the *winning* row back unchanged, so
        // both attempts drive the same aggregate id — `ON CONFLICT DO UPDATE`
        // with a no-op set is how the winning row is returned by the same
        // statement (a bare `DO NOTHING` would return no row at all).
        let row = sqlx::query(
            r#"
            INSERT INTO ai_import.projection_ai_import_mapping
                (preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (preview_id, draft_ref, aggregate_kind, ordinal) DO UPDATE
                SET aggregate_kind = ai_import.projection_ai_import_mapping.aggregate_kind
            RETURNING preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version
            "#,
        )
            .bind(mapping.preview_id.as_uuid())
            .bind(&mapping.draft_ref)
            .bind(&mapping.aggregate_kind)
            .bind(mapping.ordinal)
            .bind(mapping.aggregate_id)
            .bind(version_to_db(mapping.aggregate_version)?)
            .fetch_optional(&self.pool)
            .await
            .map_err(map_sqlx_error)?;
        match row {
            Some(row) => map_mapping(row),
            // The row vanished between conflict and return (a concurrent
            // delete). Re-read rather than invent: the caller must drive the
            // winner's id, never the id it proposed.
            None => self
                .find(
                    mapping.preview_id,
                    &mapping.draft_ref,
                    &mapping.aggregate_kind,
                    mapping.ordinal,
                )
                .await?
                .ok_or_else(|| {
                    DomainError::service_unavailable(
                        "AI mapping reservation vanished after conflict",
                    )
                }),
        }
    }

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        // Monotonic advance only: a late duplicate (or a stale retry that still
        // holds a reservation's version 0) must never roll a confirmed row
        // back. The `WHERE` belongs to the `DO UPDATE`, not the statement, so a
        // non-advancing write simply affects zero rows.
        sqlx::query(
            r#"
            INSERT INTO ai_import.projection_ai_import_mapping
                (preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (preview_id, draft_ref, aggregate_kind, ordinal) DO UPDATE
            SET aggregate_kind = EXCLUDED.aggregate_kind,
                aggregate_id = EXCLUDED.aggregate_id,
                aggregate_version = EXCLUDED.aggregate_version,
                updated_at = now()
            WHERE ai_import.projection_ai_import_mapping.aggregate_version
                < EXCLUDED.aggregate_version
            "#,
        )
        .bind(mapping.preview_id.as_uuid())
        .bind(&mapping.draft_ref)
        .bind(&mapping.aggregate_kind)
        .bind(mapping.ordinal)
        .bind(mapping.aggregate_id)
        .bind(version_to_db(mapping.aggregate_version)?)
        .execute(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError> {
        // Every kind is returned — scene, character and costume rows included —
        // in a stable order, so a re-import of an updated document can re-suggest
        // the prior mapping for each of them (task 4.3).
        let rows = sqlx::query(
            r#"
            SELECT preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id, aggregate_version
            FROM ai_import.projection_ai_import_mapping
            WHERE preview_id = $1
            ORDER BY draft_ref, aggregate_kind, ordinal
            "#,
        )
        .bind(preview_id.as_uuid())
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        rows.into_iter().map(map_mapping).collect()
    }
}

#[async_trait::async_trait]
impl<M: AiImportMappingRepository> AiImportMappingRepository for CachedMappings<M> {
    async fn find(
        &self,
        preview_id: AiImportJobId,
        draft_ref: &str,
        aggregate_kind: &str,
        ordinal: i32,
    ) -> Result<Option<AiImportMapping>, DomainError> {
        let key = mapping_key(preview_id, draft_ref, aggregate_kind, ordinal);
        if let Some(known) = self.lookup(&key) {
            return Ok(known);
        }
        let found = self
            .inner
            .find(preview_id, draft_ref, aggregate_kind, ordinal)
            .await?;
        // Only a hit is cached here: a miss from a single-row read does not
        // prove absence (another run may still confirm it), while a hit is the
        // store's own monotonic truth. The `complete` set covers the misses.
        if let Some(row) = found.as_ref() {
            self.write().rows.insert(key, row.clone());
        }
        Ok(found)
    }

    async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError> {
        let key = mapping_key(
            mapping.preview_id,
            &mapping.draft_ref,
            &mapping.aggregate_kind,
            mapping.ordinal,
        );
        let won = self.inner.reserve(mapping).await?;
        // The winning row is authoritative — insert-if-absent returned the row
        // that is actually persisted, which is the id every later step must use.
        self.write().rows.insert(key, won.clone());
        Ok(won)
    }

    async fn insert(&self, mapping: AiImportMapping) -> Result<(), DomainError> {
        let key = mapping_key(
            mapping.preview_id,
            &mapping.draft_ref,
            &mapping.aggregate_kind,
            mapping.ordinal,
        );
        let next = mapping.clone();
        self.inner.insert(mapping).await?;
        let mut snapshot = self.write();
        // Only mirror `next` when the cache can prove the SQL `WHERE
        // aggregate_version < EXCLUDED.aggregate_version` guard accepted it:
        // either we already hold the row at a lower version, or `complete`
        // proves no row existed in the store. For an unprimed unknown key,
        // leave the cache empty so a later `find` reads the store's winner.
        let advances = match snapshot.rows.get(&key) {
            Some(current) => current.aggregate_version < next.aggregate_version,
            None => snapshot.complete.contains(&key.0),
        };
        if advances {
            snapshot.rows.insert(key, next);
        }
        Ok(())
    }

    async fn list_by_preview(
        &self,
        preview_id: AiImportJobId,
    ) -> Result<Vec<AiImportMapping>, DomainError> {
        // A decorator of the port, not a write-side consumer: this call IS the
        // repository implementation the apply's idempotency read goes through,
        // and it resolves no audit context (no `project_id`, no season).
        let rows = self
            .inner
            .list_by_preview(preview_id) // ast-grep-ignore: cqrs-boundary
            .await?;
        let mut snapshot = self.write();
        // Replace this preview's slice wholesale: the listing is the complete
        // truth, so a row that vanished (a dev reset) must vanish here too.
        snapshot.rows.retain(|key, _| key.0 != preview_id);
        for row in &rows {
            snapshot.rows.insert(
                mapping_key(
                    row.preview_id,
                    &row.draft_ref,
                    &row.aggregate_kind,
                    row.ordinal,
                ),
                row.clone(),
            );
        }
        snapshot.complete.insert(preview_id);
        Ok(rows)
    }
}

/// Checked `u64 -> i64` conversion: an `as` cast would silently wrap above
/// `i64::MAX` and persist a negative row that the read path rejects
/// (`map_mapping`) — fail loudly instead.
fn version_to_db(version: breakdown_core::shared::AggregateVersion) -> Result<i64, DomainError> {
    i64::try_from(version.0).map_err(|error| {
        DomainError::validation(format!(
            "AI mapping aggregate version exceeds database range: {error}"
        ))
    })
}

fn map_mapping(row: sqlx::postgres::PgRow) -> Result<AiImportMapping, DomainError> {
    let preview_id: Uuid = row.try_get("preview_id").map_err(map_sqlx_error)?;
    let aggregate_version: i64 = row.try_get("aggregate_version").map_err(map_sqlx_error)?;
    if aggregate_version < 0 {
        return Err(DomainError::validation(
            "AI mapping aggregate version cannot be negative",
        ));
    }
    let ordinal: i32 = row.try_get("ordinal").map_err(map_sqlx_error)?;
    if ordinal < PRIMARY_ORDINAL {
        // A negative ordinal would be unreadable by every `find` the apply
        // performs, so surface the corruption instead of carrying it.
        return Err(DomainError::validation(
            "AI mapping ordinal cannot be negative",
        ));
    }
    Ok(AiImportMapping {
        preview_id: AiImportJobId::from_uuid(preview_id),
        draft_ref: row.try_get("draft_ref").map_err(map_sqlx_error)?,
        aggregate_kind: row.try_get("aggregate_kind").map_err(map_sqlx_error)?,
        ordinal,
        aggregate_id: row.try_get("aggregate_id").map_err(map_sqlx_error)?,
        aggregate_version: breakdown_core::shared::AggregateVersion(aggregate_version as u64),
    })
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    // The mapping table is operational state, not business truth; a database
    // failure is always retryable from the caller's point of view.
    tracing::error!(%error, "AI mapping database error");
    DomainError::service_unavailable("AI mapping database error")
}
