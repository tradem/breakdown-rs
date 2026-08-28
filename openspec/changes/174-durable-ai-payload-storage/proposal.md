# Proposal: Durable AI Payload Storage (Issue #174)

## Problem

`MemoryAiPreviewStore` is used in production. Source documents (PDFs/CSVs) and preview payloads (JSON) are stored in process memory only. After an API restart:

- Pending jobs cannot resume (source bytes lost)
- Failed jobs cannot retry (source bytes lost)
- Succeeded jobs cannot serve previews (preview bytes lost)
- Apply operations fail for succeeded jobs (preview bytes lost)

## Solution

Replace `MemoryAiPreviewStore` with `OpenDalAiPayloadStorage` backed by Garage (S3-compatible object store), consistent with the existing photo storage pattern.

## Key Decisions

- **Storage backend**: OpenDAL/Garage (S3-compatible) — consistent with photo storage
- **Bucket**: Separate bucket `ai-import-payloads` (isolated from `costume-photos`)
- **Key layout**: `ai-import/{job_id}/source` and `ai-import/{job_id}/preview`
- **Retention**: Payloads deleted after job reaches terminal state (succeeded/failed/dead_letter) + configurable grace period
- **No SSE-C encryption**: Unlike photos, AI payloads don't contain PII — plain S3 storage is sufficient

## Implementation Steps

### Phase 1: Core Infrastructure

1. Create `OpenDalAiPayloadStorage` adapter in `crates/infra/src/ai/payload_storage.rs`
2. Implement `AiPreviewStore` and `AiDocumentSource` traits
3. Add environment variables (`AI_PAYLOAD_S3_*`) for bucket configuration

### Phase 2: Queue Integration

4. Update `PgAiImportQueue` to track payload lifecycle
5. Add `payload_stored_at` timestamp to `ai_import_job` table
6. Create migration for new columns

### Phase 3: Cleanup Worker

7. Implement `AiPayloadCleanupWorker` to delete payloads from terminal jobs
8. Configurable retention period (default: 7 days after terminal state)

### Phase 4: Production Wiring

9. Update `main.rs` to use `OpenDalAiPayloadStorage` when S3 is configured
10. Fall back to `MemoryAiPreviewStore` for local development without S3

### Phase 5: Testing

11. Unit tests for storage adapter
12. Integration tests for restart-recovery scenario
13. Test cleanup worker behavior

## Affected Files

- `crates/infra/src/ai/payload_storage.rs` (new)
- `crates/infra/src/ai/mod.rs`
- `crates/infra/src/ai/queue.rs`
- `crates/infra/migrations/XXXX_ai_payload_storage.up.sql` (new)
- `crates/api/src/main.rs`
- `crates/api/src/state.rs`
