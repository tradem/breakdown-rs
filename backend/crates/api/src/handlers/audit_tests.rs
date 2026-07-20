// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use axum::Json;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use breakdown_core::audit::AuditEntry;
use breakdown_core::shared::{BlockId, UserId};
use chrono::Utc;
use serde_json::json;
use utoipa::OpenApi;
use uuid::Uuid;

use super::get_block_audit;
use super::test_helpers::*;
use crate::state::AppState;

#[tokio::test]
async fn get_block_audit_returns_journal_entries_for_block() {
    let ports = FakePorts::default();
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    ports.audit_repo.entries.lock().await.push(AuditEntry {
        id: Uuid::now_v7(),
        entity_type: "membership".to_string(),
        entity_id: block_id.0.to_string(),
        event_type: "OwnerBootstrapped".to_string(),
        block_id: Some(block_id),
        series_id: None,
        actor: Some(UserId::from_sub("user-1")),
        payload: json!({ "role": "costume_assistant" }),
        occurred_at: Utc::now(),
    });

    let result = get_block_audit::<FakePorts>(
        State(AppState::new(ports)),
        Path(block_id.0),
        Query(super::ListParams {
            limit: Some(10),
            offset: Some(0),
            episode_id: None,
            season_id: None,
            series_id: None,
        }),
    )
    .await;

    let (status, Json(entries)) = result.expect("audit query should succeed");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].entity_type, "membership");
    assert_eq!(entries[0].event_type, "OwnerBootstrapped");
    assert_eq!(
        entries[0].actor.as_ref().map(|u| u.as_str()),
        Some("user-1")
    );
}

#[test]
fn openapi_doc_includes_block_audit_path_and_schema() {
    let doc = crate::ApiDoc::openapi();
    let json = serde_json::to_string(&doc).expect("ApiDoc serializes to JSON");
    assert!(
        json.contains("/blocks/{id}/audit"),
        "GET /blocks/{{id}}/audit must be registered in ApiDoc"
    );
    assert!(
        json.contains("AuditEntry"),
        "AuditEntry schema must be registered in ApiDoc components"
    );
    // §10 membership-management endpoints
    for path in [
        "/blocks/{id}/members",
        "/blocks/{id}/members/accept",
        "/blocks/{id}/members/leave",
        "/blocks/{id}/members/{user_id}/role",
        "/blocks/{id}/members/{user_id}",
    ] {
        assert!(
            json.contains(path),
            "membership path {path} must be registered in ApiDoc"
        );
    }
    for schema in [
        "MembershipView",
        "InviteMemberRequest",
        "GrantRoleRequest",
        "Role",
    ] {
        assert!(
            json.contains(schema),
            "{schema} schema must be registered in ApiDoc components"
        );
    }
}
