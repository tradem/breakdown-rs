// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::{AiImportBounds, DocumentKind, Telemetry};
use breakdown_core::error::DomainError;
use reqwest::StatusCode;

use super::{AiImportFeature, classify_http_status, merge_loaded_schedule, validate_chunk_count};

#[test]
fn transient_provider_statuses_are_service_unavailable() {
    assert!(matches!(
        classify_http_status(StatusCode::TOO_MANY_REQUESTS),
        DomainError::ServiceUnavailable(_)
    ));
    assert!(matches!(
        classify_http_status(StatusCode::INTERNAL_SERVER_ERROR),
        DomainError::ServiceUnavailable(_)
    ));
    assert!(matches!(
        classify_http_status(StatusCode::BAD_REQUEST),
        DomainError::ValidationError(_)
    ));
}

#[test]
fn oversized_script_is_rejected_before_provider_calls() {
    assert!(validate_chunk_count(3, 2).is_err());
    assert!(validate_chunk_count(2, 2).is_ok());
}

#[test]
fn merge_blocks_when_no_applied_scenes_exist() {
    let schedule = breakdown_core::ai::ShootingSchedule::default();
    let result = merge_loaded_schedule(&schedule, &[]);
    assert!(matches!(result, Err(DomainError::Conflict(_))));
}

#[test]
fn telemetry_serialization_is_content_free() {
    let telemetry = Telemetry {
        doc_kind: Some(DocumentKind::Script),
        chunk_count: 2,
        tokens_in: 10,
        tokens_out: 20,
        accept_as_is: Some(true),
        edit_distance: 0,
        ..Telemetry::default()
    };
    let serialized = serde_json::to_string(&telemetry).expect("telemetry is serializable in test");
    assert!(!serialized.contains("script text"));
    assert!(!serialized.contains("costume description"));
}

#[test]
fn feature_flag_parser_is_off_for_unrecognised_values() {
    assert!(!AiImportFeature::from_enabled_value("maybe").enabled);
    assert!(AiImportFeature::from_enabled_value("true").enabled);
    assert_eq!(AiImportBounds::default().max_chunks_per_script, 128);
}
