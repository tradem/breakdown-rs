// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::error::SceneError;
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::shared::{AggregateVersion, EpisodeId};
use chrono::Utc;
use infra::event_store::{
    map_executed, map_executed_result, map_version_only, version_from_expected,
};
use kameo_es::command_service::{AppendedEvent, ExecuteResult};
use kameo_es::error::ExecuteError;
use uuid::Uuid;

/// Build a single appended event carrying the given SierraDB (0-based) stream version.
fn appended_event(stream_version: u64) -> AppendedEvent<SceneEvent> {
    AppendedEvent {
        event: SceneEvent::SceneCreated {
            id: Uuid::nil(),
            episode_id: EpisodeId::new(),
            details: SceneDetails::default(),
            assigned_characters: Vec::new(),
            version: AggregateVersion(1),
        },
        event_id: Uuid::nil(),
        partition_id: 0,
        partition_sequence: 0,
        stream_version,
        timestamp: Utc::now(),
    }
}

/// The result type the helpers operate on, pinned to a concrete entity/error so the
/// otherwise-unconstrained generic parameters resolve.
type ExecResult = Result<ExecuteResult<SceneAggregate>, ExecuteError<SceneError>>;

#[test]
fn map_executed_result_uses_last_event_stream_version() {
    let id = Uuid::now_v7();
    // Two events: the mapped version must come from the *last* event's stream version.
    let result: ExecResult = Ok(ExecuteResult::Executed(vec![
        appended_event(0),
        appended_event(4),
    ]));
    let (rid, version) = map_executed_result(id, result).unwrap();
    assert_eq!(rid, id);
    // stream_version 4 -> domain version 5
    assert_eq!(version, AggregateVersion(5));
}

#[test]
fn map_executed_result_idempotent_current() {
    let id = Uuid::now_v7();
    let result: ExecResult = Ok(ExecuteResult::Idempotent {
        current_version: sierradb_client::CurrentVersion::Current(2),
    });
    let (rid, version) = map_executed_result(id, result).unwrap();
    assert_eq!(rid, id);
    assert_eq!(version, AggregateVersion(3));
}

#[test]
fn map_executed_result_idempotent_empty() {
    let id = Uuid::now_v7();
    let result: ExecResult = Ok(ExecuteResult::Idempotent {
        current_version: sierradb_client::CurrentVersion::Empty,
    });
    let (rid, version) = map_executed_result(id, result).unwrap();
    assert_eq!(rid, id);
    assert_eq!(version, AggregateVersion(0));
}

#[test]
fn map_executed_result_handle_error_is_domain_error() {
    let id = Uuid::now_v7();
    let result: ExecResult = Err(ExecuteError::Handle(SceneError::ValidationError(
        "boom".into(),
    )));
    let err = map_executed_result(id, result).unwrap_err();
    assert!(matches!(
        err,
        breakdown_core::error::DomainError::Validation { .. }
    ));
}

#[test]
fn map_version_only_discards_id_and_returns_version() {
    // Use a non-initial stream version so the mapped domain version (5) differs from
    // `AggregateVersion::default()` (== INITIAL == 1), which the "replace body with
    // Ok(Default::default())" mutant would otherwise return and go undetected.
    let result: ExecResult = Ok(ExecuteResult::Executed(vec![appended_event(4)]));
    let version = map_version_only(result).unwrap();
    assert_eq!(version, AggregateVersion(5));
}

#[test]
fn map_executed_preserves_id_and_returns_version() {
    let id = Uuid::now_v7();
    let result: ExecResult = Ok(ExecuteResult::Executed(vec![appended_event(2)]));
    let (rid, version) = map_executed(id, result).unwrap();
    assert_eq!(rid, id);
    assert_eq!(version, AggregateVersion(3));
}

#[test]
fn version_from_expected_maps_exact_and_empty() {
    // `Exact(v)` maps to the literal domain version `v`.
    assert_eq!(
        version_from_expected(sierradb_client::ExpectedVersion::Exact(5)),
        AggregateVersion(5)
    );
    // `Empty` and any other variant map to the initial domain version.
    assert_eq!(
        version_from_expected(sierradb_client::ExpectedVersion::Empty),
        AggregateVersion::INITIAL
    );
    assert_eq!(
        version_from_expected(sierradb_client::ExpectedVersion::Any),
        AggregateVersion::INITIAL
    );
}
