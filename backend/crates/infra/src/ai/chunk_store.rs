// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Durable per-chunk extraction results (issue #871, workstream B).
//!
//! Two properties carry the design and are easy to get subtly wrong:
//!
//! 1. **The write is claim-fenced by a row LOCK, not a predicate.** Under READ
//!    COMMITTED a bare `INSERT … SELECT … WHERE status = 'running' AND worker_id
//!    = $2` reads the job row without a lock, so another session can reclaim the
//!    job and rewrite `extraction_key` between the read and the commit — and the
//!    stale write lands anyway. The `claim_lost` heartbeat check does not close
//!    that window either: it is a check, not a lock. Every write therefore takes
//!    the job row `FOR UPDATE` first, and the **invalidation path takes the same
//!    lock on the same row in the same order**, so the two serialize instead of
//!    interleaving.
//!
//! 2. **The resume cursor is derived, never stored** (D-B2): the length of the
//!    contiguous stored prefix. `MAX(chunk_index) + 1` over `0, 1, 3` would
//!    answer 4 and quietly omit chunk 2 from the preview.

use breakdown_core::ai::ports::{
    AiImportChunkStore, ChunkSetState, ExtractionFingerprint, StoredChunk, resume_cursor,
};
use breakdown_core::ai::{AiImportJobId, ScriptContext};
use breakdown_core::error::DomainError;
use sqlx::{PgPool, Row};

/// Postgres-backed [`AiImportChunkStore`].
#[derive(Debug, Clone)]
pub struct PgAiImportChunkStore {
    pool: PgPool,
}

impl PgAiImportChunkStore {
    #[must_use]
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Open an attempt's chunk set: compare-and-set the extraction fingerprint
    /// and drop the stored chunks when it changed (D-B7).
    ///
    /// Runs in **one transaction that takes the job row `FOR UPDATE` first** —
    /// the same lock and order as [`AiImportChunkStore::put`] — so an
    /// invalidation can never interleave with a chunk write from a worker that
    /// is about to lose its claim.
    async fn begin_extraction_locked(
        &self,
        job_id: AiImportJobId,
        worker_id: &str,
        fingerprint: &ExtractionFingerprint,
        key: &str,
    ) -> Result<ChunkSetState, DomainError> {
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;
        // Step 1: the lock, and the claim it protects.
        let row = sqlx::query(
            r#"
            SELECT status, worker_id, extraction_key, extraction_key_components
            FROM ai_import.ai_import_job
            WHERE id = $1
            FOR UPDATE
            "#,
        )
        .bind(job_id.as_uuid())
        .fetch_optional(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        let Some(row) = row else {
            return Err(DomainError::not_found("ai import job not found"));
        };
        ensure_running_and_owned(&row, worker_id)?;

        let stored_key: Option<String> = row.try_get("extraction_key").map_err(map_sqlx_error)?;
        let stored_components: Option<serde_json::Value> = row
            .try_get("extraction_key_components")
            .map_err(map_sqlx_error)?;
        let changed = match (stored_key.as_deref(), stored_components) {
            (Some(stored_key), Some(components)) if stored_key == key => {
                // Same hash: nothing to do. The components are re-decoded only so
                // a hash collision (or a hand-edited row) cannot silently pass.
                match serde_json::from_value::<ExtractionFingerprint>(components) {
                    Ok(previous) => previous.changed_components(fingerprint),
                    // An undecodable component blob cannot be trusted to be
                    // compatible — invalidate rather than resume across it.
                    Err(_) => vec!["components_unreadable"],
                }
            }
            (Some(_), _) => {
                // A different key with (unexpectedly) unreadable components: the
                // hash is authoritative for the verdict.
                vec!["extraction_key"]
            }
            (None, _) => {
                // No stored set yet: nothing to invalidate, but the fingerprint
                // must still be WRITTEN — `put` fences every chunk write on it, so
                // a fresh attempt that skipped this would have its first chunk
                // rejected. Compare-and-set, so a concurrent attempt that wrote
                // one first wins and this one then re-reads on its next call.
                sqlx::query(
                    r#"
                    UPDATE ai_import.ai_import_job
                    SET extraction_key = $2,
                        extraction_key_components = $3,
                        updated_at = now()
                    WHERE id = $1 AND extraction_key IS NULL
                    "#,
                )
                .bind(job_id.as_uuid())
                .bind(key)
                .bind(serde_json::to_value(fingerprint).map_err(|error| {
                    DomainError::validation(format!(
                        "extraction fingerprint is not serializable: {error}"
                    ))
                })?)
                .execute(&mut *tx)
                .await
                .map_err(map_sqlx_error)?;
                tx.commit().await.map_err(map_sqlx_error)?;
                return Ok(ChunkSetState::Compatible);
            }
        };
        if changed.is_empty() {
            tx.commit().await.map_err(map_sqlx_error)?;
            return Ok(ChunkSetState::Compatible);
        }

        // Step 2: same transaction, same lock order — delete the chunks, then
        // write the new fingerprint. Never a partial resume across two models.
        let deleted = sqlx::query("DELETE FROM ai_import.ai_import_job_chunk WHERE job_id = $1")
            .bind(job_id.as_uuid())
            .execute(&mut *tx)
            .await
            .map_err(map_sqlx_error)?
            .rows_affected();
        sqlx::query(
            r#"
            UPDATE ai_import.ai_import_job
            SET extraction_key = $2,
                extraction_key_components = $3,
                updated_at = now()
            WHERE id = $1
            "#,
        )
        .bind(job_id.as_uuid())
        .bind(key)
        .bind(serde_json::to_value(fingerprint).map_err(|error| {
            DomainError::validation(format!(
                "extraction fingerprint is not serializable: {error}"
            ))
        })?)
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        tx.commit().await.map_err(map_sqlx_error)?;
        tracing::warn!(
            job_id = %job_id.as_uuid(),
            components = ?changed,
            deleted_chunks = deleted,
            "#871 chunk resume invalidated: the stored chunks belong to a different configuration"
        );
        Ok(ChunkSetState::Invalidated(changed))
    }
}

/// The stored extraction fingerprint of one job, if any.
pub async fn stored_fingerprint(
    pool: &PgPool,
    job_id: AiImportJobId,
) -> Result<Option<ExtractionFingerprint>, DomainError> {
    let components: Option<serde_json::Value> = sqlx::query_scalar(
        "SELECT extraction_key_components FROM ai_import.ai_import_job WHERE id = $1",
    )
    .bind(job_id.as_uuid())
    .fetch_optional(pool)
    .await
    .map_err(map_sqlx_error)?
    .flatten();
    match components {
        Some(value) => serde_json::from_value(value).map(Some).map_err(|error| {
            DomainError::validation(format!(
                "stored extraction fingerprint is undecodable: {error}"
            ))
        }),
        None => Ok(None),
    }
}

#[async_trait::async_trait]
impl AiImportChunkStore for PgAiImportChunkStore {
    async fn begin_extraction(
        &self,
        job_id: AiImportJobId,
        worker_id: &str,
        fingerprint: &ExtractionFingerprint,
        key: &str,
    ) -> Result<ChunkSetState, DomainError> {
        self.begin_extraction_locked(job_id, worker_id, fingerprint, key)
            .await
    }

    async fn load(&self, job_id: AiImportJobId) -> Result<Vec<StoredChunk>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT chunk_index, payload, usage
            FROM ai_import.ai_import_job_chunk
            WHERE job_id = $1
            ORDER BY chunk_index
            "#,
        )
        .bind(job_id.as_uuid())
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        let mut chunks = Vec::with_capacity(rows.len());
        for row in rows {
            let chunk_index: i32 = row.try_get("chunk_index").map_err(map_sqlx_error)?;
            let payload: serde_json::Value = row.try_get("payload").map_err(map_sqlx_error)?;
            let usage: serde_json::Value = row.try_get("usage").map_err(map_sqlx_error)?;
            chunks.push(StoredChunk {
                chunk_index: u32::try_from(chunk_index).unwrap_or(0),
                payload: serde_json::from_value(payload).map_err(|error| {
                    DomainError::validation(format!("stored chunk payload is undecodable: {error}"))
                })?,
                usage: serde_json::from_value(usage).map_err(|error| {
                    DomainError::validation(format!("stored chunk usage is undecodable: {error}"))
                })?,
            });
        }

        // D-B2: a row beyond a hole is unreachable — the merge pass is a prefix
        // walk — so it can only be garbage. Delete the tail and say so.
        let prefix = resume_cursor(&chunks);
        if chunks.len() > prefix as usize {
            let hole = prefix;
            let deleted = sqlx::query(
                r#"
                DELETE FROM ai_import.ai_import_job_chunk
                WHERE job_id = $1 AND chunk_index >= $2
                "#,
            )
            .bind(job_id.as_uuid())
            .bind(i32::try_from(hole).unwrap_or(i32::MAX))
            .execute(&self.pool)
            .await
            .map_err(map_sqlx_error)?
            .rows_affected();
            tracing::warn!(
                job_id = %job_id.as_uuid(),
                hole,
                deleted,
                "#871 chunk resume hole at {hole}: the tail beyond it is unreachable and was deleted"
            );
            chunks.truncate(prefix as usize);
        }
        Ok(chunks)
    }

    async fn put(
        &self,
        job_id: AiImportJobId,
        worker_id: &str,
        extraction_key: &str,
        chunk: &StoredChunk,
    ) -> Result<(), DomainError> {
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;
        // The lock comes first — see the module doc.
        let row = sqlx::query(
            r#"
            SELECT status, worker_id, extraction_key
            FROM ai_import.ai_import_job
            WHERE id = $1
            FOR UPDATE
            "#,
        )
        .bind(job_id.as_uuid())
        .fetch_optional(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        let Some(row) = row else {
            return Err(DomainError::not_found("ai import job not found"));
        };
        ensure_running_and_owned(&row, worker_id)?;
        let stored_key: Option<String> = row.try_get("extraction_key").map_err(map_sqlx_error)?;
        if stored_key.as_deref() != Some(extraction_key) {
            // Another worker reclaimed the job and invalidated the set between
            // our attempt start and this write.
            return Err(DomainError::conflict(
                "the chunk set was invalidated by another attempt",
            ));
        }
        sqlx::query(
            r#"
            INSERT INTO ai_import.ai_import_job_chunk
                (job_id, chunk_index, payload, usage)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (job_id, chunk_index) DO UPDATE
                SET payload = EXCLUDED.payload,
                    usage = EXCLUDED.usage
            "#,
        )
        .bind(job_id.as_uuid())
        .bind(i32::try_from(chunk.chunk_index).unwrap_or(i32::MAX))
        .bind(serde_json::to_value(&chunk.payload).map_err(|error| {
            DomainError::validation(format!("chunk payload is not serializable: {error}"))
        })?)
        .bind(serde_json::to_value(chunk.usage).map_err(|error| {
            DomainError::validation(format!("chunk usage is not serializable: {error}"))
        })?)
        .execute(&mut *tx)
        .await
        .map_err(map_sqlx_error)?;
        tx.commit().await.map_err(map_sqlx_error)?;
        Ok(())
    }

    async fn clear(&self, job_id: AiImportJobId) -> Result<u64, DomainError> {
        let result = sqlx::query("DELETE FROM ai_import.ai_import_job_chunk WHERE job_id = $1")
            .bind(job_id.as_uuid())
            .execute(&self.pool)
            .await
            .map_err(map_sqlx_error)?;
        Ok(result.rows_affected())
    }
}

/// `sha256(document_digest | provider | model | prompt_hash | chunker_version)`.
///
/// The one authoritative rendering of the fingerprint (D-B7). Length-prefixing is
/// deliberately omitted: the components are a digest (hex), two provider/model
/// keys and a hex hash, none of which can contain the `|` separator, so the
/// concatenation is unambiguous.
#[must_use]
pub fn fingerprint_key(fingerprint: &ExtractionFingerprint) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(fingerprint.document_digest.as_bytes());
    hasher.update(b"|");
    hasher.update(fingerprint.provider.as_str().as_bytes());
    hasher.update(b"|");
    hasher.update(fingerprint.model.as_bytes());
    hasher.update(b"|");
    hasher.update(fingerprint.prompt_hash.as_bytes());
    hasher.update(b"|");
    hasher.update(fingerprint.chunker_version.to_string().as_bytes());
    hex(&hasher.finalize())
}

/// `sha256` of the prompt text actually sent (D-B7).
#[must_use]
pub fn prompt_hash(prompt: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(prompt.as_bytes());
    hex(&hasher.finalize())
}

/// Lower-case hex of a digest (sha2 0.11's output array has no `LowerHex`).
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// The claim fence shared by both write paths.
fn ensure_running_and_owned(
    row: &sqlx::postgres::PgRow,
    worker_id: &str,
) -> Result<(), DomainError> {
    let status: String = row.try_get("status").map_err(map_sqlx_error)?;
    let owner: Option<String> = row.try_get("worker_id").map_err(map_sqlx_error)?;
    if status != "running" || owner.as_deref() != Some(worker_id) {
        tracing::warn!(
            worker_id,
            status,
            owner = owner.as_deref().unwrap_or("<none>"),
            "AI import chunk store refused a write: the claim is gone"
        );
        return Err(DomainError::conflict(format!(
            "worker {worker_id} no longer holds the claim on this AI import job"
        )));
    }
    Ok(())
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    match error {
        sqlx::Error::RowNotFound => DomainError::not_found("row not found"),
        other => DomainError::service_unavailable(format!("database error: {other}")),
    }
}

/// `true` when the job row's `ScriptContext` payload shape is what this build
/// writes. Kept for the tests' benefit: a payload written by another build
/// decodes through `serde(default)` and stays resumable.
#[must_use]
pub fn payload_is_decodable(value: &serde_json::Value) -> bool {
    serde_json::from_value::<ScriptContext>(value.clone()).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use breakdown_core::ai::LlmProvider;

    fn fingerprint(model: &str, prompt_hash: &str) -> ExtractionFingerprint {
        ExtractionFingerprint {
            document_digest: "digest".to_owned(),
            provider: LlmProvider::OpenCodeGo,
            model: model.to_owned(),
            prompt_hash: prompt_hash.to_owned(),
            chunker_version: breakdown_core::ai::preview::CHUNKER_VERSION,
        }
    }

    #[test]
    fn the_key_is_stable_and_component_sensitive() {
        let base = fingerprint_key(&fingerprint("m", "p"));
        assert_eq!(base, fingerprint_key(&fingerprint("m", "p")));
        assert_ne!(base, fingerprint_key(&fingerprint("other-model", "p")));
        assert_ne!(base, fingerprint_key(&fingerprint("m", "other-prompt")));
        // 64 hex chars, i.e. sha256.
        assert_eq!(base.len(), 64);
    }

    #[test]
    fn changed_components_names_what_moved() {
        let a = fingerprint("m", "p");
        let mut b = a.clone();
        b.model = "m2".to_owned();
        b.chunker_version += 1;
        assert_eq!(b.changed_components(&a), vec!["model", "chunker_version"]);
        assert!(a.changed_components(&a).is_empty());
    }

    #[test]
    fn the_prompt_hash_depends_on_whitespace() {
        // A whitespace-only prompt edit CAN change model output, so
        // re-invalidating on it is correct rather than an over-reaction (D-B7).
        assert_ne!(prompt_hash("line one"), prompt_hash("line  one"));
    }
}
