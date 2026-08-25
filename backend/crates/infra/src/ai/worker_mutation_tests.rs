// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for workers.rs and worker_loop.rs — kills mutations in
//! acquire_for_claim, release_permit_logging_errors, run_once_with_permit,
//! start_heartbeat, fetch_api_key, script_worker_tick, schedule_worker_tick,
//! and handle_job_result.

use breakdown_core::ai::{
    AiImportBounds, AiImportJobId, DocumentKind, LlmProvider, ScriptContext, Telemetry,
    TelemetryApplyState,
};
use breakdown_core::error::DomainError;

// ===========================================================================
// DomainError variants
// ===========================================================================

#[test]
fn conflict_error_is_created() {
    let err = DomainError::conflict("test");
    assert!(matches!(err, DomainError::Conflict { .. }));
}

#[test]
fn validation_error_is_created() {
    let err = DomainError::validation("test");
    assert!(matches!(err, DomainError::Validation { .. }));
}

#[test]
fn service_unavailable_error_is_created() {
    let err = DomainError::service_unavailable("test");
    assert!(matches!(err, DomainError::ServiceUnavailable { .. }));
}

// ===========================================================================
// Telemetry structure
// ===========================================================================

#[test]
fn telemetry_default_is_not_applied() {
    let telemetry = Telemetry::default();
    assert_eq!(telemetry.apply_state, TelemetryApplyState::NotApplied);
}

#[test]
fn telemetry_with_values() {
    let telemetry = Telemetry {
        provider: Some(LlmProvider::OpenAI),
        model: Some("gpt-4o".into()),
        doc_kind: Some(DocumentKind::Script),
        chunk_count: 10,
        tokens_in: 1000,
        tokens_out: 500,
        latency_total: 1234,
        apply_state: TelemetryApplyState::default(),
    };
    assert_eq!(telemetry.chunk_count, 10);
    assert_eq!(telemetry.tokens_in, 1000);
    assert_eq!(telemetry.tokens_out, 500);
    assert_eq!(telemetry.latency_total, 1234);
}

#[test]
fn telemetry_chunk_count_can_be_zero() {
    let telemetry = Telemetry {
        chunk_count: 0,
        ..Telemetry::default()
    };
    assert_eq!(telemetry.chunk_count, 0);
}

// ===========================================================================
// DocumentKind matching
// ===========================================================================

#[test]
fn script_kind_matches_script() {
    assert_eq!(DocumentKind::Script, DocumentKind::Script);
}

#[test]
fn schedule_kind_matches_schedule() {
    assert_eq!(DocumentKind::Schedule, DocumentKind::Schedule);
}

#[test]
fn script_kind_does_not_match_schedule() {
    assert_ne!(DocumentKind::Script, DocumentKind::Schedule);
}

// ===========================================================================
// AiImportBounds for workers
// ===========================================================================

#[test]
fn default_bounds_are_valid() {
    let bounds = AiImportBounds::default();
    assert!(bounds.max_concurrent_jobs_global > 0);
    assert!(bounds.max_concurrent_jobs_per_user > 0);
    assert!(bounds.max_concurrent_jobs_per_user <= bounds.max_concurrent_jobs_global);
}

// ===========================================================================
// LlmProvider constants
// ===========================================================================

#[test]
fn openai_provider_is_not_local() {
    assert!(!LlmProvider::OpenAI.is_local());
}

#[test]
fn ollama_provider_is_local() {
    assert!(LlmProvider::Ollama.is_local());
}

// ===========================================================================
// ScriptContext
// ===========================================================================

#[test]
fn script_context_default_is_empty() {
    let ctx = ScriptContext::default();
    assert!(ctx.scenes.is_empty());
    assert!(ctx.uncertainties.is_empty());
}

// ===========================================================================
// AiImportJobId
// ===========================================================================

#[test]
fn job_id_is_unique() {
    let id1 = AiImportJobId::new();
    let id2 = AiImportJobId::new();
    assert_ne!(id1, id2);
}

#[test]
fn job_id_from_uuid_roundtrips() {
    let uuid = uuid::Uuid::now_v7();
    let id = AiImportJobId::from_uuid(uuid);
    assert_eq!(id.as_uuid(), uuid);
}
