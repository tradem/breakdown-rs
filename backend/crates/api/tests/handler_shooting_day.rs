// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

//! Handler tests for `PATCH /shooting-days/{id}` explicit clear (issue #372).
//!
//! `UpdateShootingDayRequest.date` / `.label` are presence-tracked
//! (`Option<Option<..>>`): an absent field means "no update", an explicit JSON
//! `null` (`Some(None)`) clears the value (unschedule / rename-to-null), and a
//! JSON value (`Some(Some(v))`) sets it. Every request below is built through
//! `serde_json` so the tests prove the distinction survives the wire —
//! constructing the struct literal directly would bypass deserialization and
//! could not catch the regression (explicit `null` collapsing to `None` and
//! falling through to `422 no update field provided`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

mod common;

use api::auth::CurrentUser;
use api::handlers::{UpdateShootingDayRequest, update_shooting_day};
use api::problems::{Json, Path};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::episode::EpisodeView;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, LexicalSortKey, SeriesId, ShootingDayId,
};
use breakdown_core::shooting_day::ShootingDayView;
use chrono::NaiveDate;
use common::FakePorts;

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy("test-user")
}

/// Seed the minimal chain `update_shooting_day` resolves at the API edge:
/// shooting_day → episode (carries `series_id` for the audit trail).
async fn seed_shooting_day_chain(ports: &FakePorts) -> ShootingDayId {
    let sd_id = ShootingDayId::new();
    let ep_id = EpisodeId::new();
    ports.episode_repo.episodes.lock().await.insert(
        ep_id.0,
        EpisodeView {
            id: ep_id.0,
            block_id: BlockId::new(),
            series_id: SeriesId::new(),
            number: 1,
            name: Some("Episode 1".into()),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    ports.shooting_day_repo.days.lock().await.insert(
        sd_id,
        ShootingDayView {
            id: sd_id,
            episode_id: ep_id,
            label: Some("Day 1".into()),
            order_key: LexicalSortKey::from_static("a"),
            date: None,
            source: breakdown_core::shooting_day::events::ShootingDaySource::Manual,
            archived: false,
            wrapped_at: None,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
    sd_id
}

fn request_from_json(value: serde_json::Value) -> UpdateShootingDayRequest {
    serde_json::from_value(value).expect("test request must deserialize")
}

#[test]
fn absent_fields_mean_no_update() {
    let req: UpdateShootingDayRequest = request_from_json(serde_json::json!({"version": 1}));
    assert_eq!(req.date, None);
    assert_eq!(req.label, None);
    assert_eq!(req.order_key, None);
}

#[test]
fn explicit_null_date_is_unschedule_not_absence() {
    let req: UpdateShootingDayRequest =
        request_from_json(serde_json::json!({"version": 1, "date": null}));
    assert_eq!(req.date, Some(None));
    assert_eq!(req.label, None);
}

#[test]
fn date_value_sets_some_date() {
    let req: UpdateShootingDayRequest =
        request_from_json(serde_json::json!({"version": 1, "date": "2026-03-14"}));
    assert_eq!(
        req.date,
        Some(Some(
            NaiveDate::from_ymd_opt(2026, 3, 14).expect("valid test date")
        ))
    );
}

#[test]
fn explicit_null_label_clears_not_absence() {
    let req: UpdateShootingDayRequest =
        request_from_json(serde_json::json!({"version": 1, "label": null}));
    assert_eq!(req.label, Some(None));
    assert_eq!(req.date, None);
}

#[test]
fn label_value_sets_some_label() {
    let req: UpdateShootingDayRequest =
        request_from_json(serde_json::json!({"version": 1, "label": "Nachtdreh"}));
    assert_eq!(req.label, Some(Some("Nachtdreh".to_owned())));
}

#[tokio::test]
async fn reschedule_with_date_dispatches_some_date() {
    let ports = FakePorts::default();
    let sd_id = seed_shooting_day_chain(&ports).await;
    let state = AppState::new(ports.clone());
    let req = request_from_json(serde_json::json!({"version": 1, "date": "2026-03-14"}));

    let result = update_shooting_day(State(state), dummy_user(), Path(sd_id), Json(req)).await;
    let (status, _) = result.expect("reschedule with date must succeed");
    assert_eq!(status, StatusCode::OK);

    let recorded = ports
        .shooting_day_commands
        .last_reschedule
        .lock()
        .await
        .clone()
        .expect("reschedule must have been dispatched");
    assert_eq!(
        recorded.date,
        Some(NaiveDate::from_ymd_opt(2026, 3, 14).expect("valid test date"))
    );
    assert!(
        ports
            .shooting_day_commands
            .last_rename
            .lock()
            .await
            .is_none(),
        "date update must not dispatch rename"
    );
}

#[tokio::test]
async fn explicit_null_date_unschedules() {
    let ports = FakePorts::default();
    let sd_id = seed_shooting_day_chain(&ports).await;
    let state = AppState::new(ports.clone());
    let req = request_from_json(serde_json::json!({"version": 1, "date": null}));

    // Regression test for issue #372: explicit `null` used to collapse to
    // `None` and fall through to `422 no update field provided`.
    let result = update_shooting_day(State(state), dummy_user(), Path(sd_id), Json(req)).await;
    let (status, _) = result.expect("explicit null date must unschedule, not 422");
    assert_eq!(status, StatusCode::OK);

    let recorded = ports
        .shooting_day_commands
        .last_reschedule
        .lock()
        .await
        .clone()
        .expect("reschedule must have been dispatched");
    assert_eq!(recorded.date, None);
}

#[tokio::test]
async fn rename_with_label_dispatches_some_label() {
    let ports = FakePorts::default();
    let sd_id = seed_shooting_day_chain(&ports).await;
    let state = AppState::new(ports.clone());
    let req = request_from_json(serde_json::json!({"version": 1, "label": "Nachtdreh"}));

    let result = update_shooting_day(State(state), dummy_user(), Path(sd_id), Json(req)).await;
    let (status, _) = result.expect("rename with label must succeed");
    assert_eq!(status, StatusCode::OK);

    let recorded = ports
        .shooting_day_commands
        .last_rename
        .lock()
        .await
        .clone()
        .expect("rename must have been dispatched");
    assert_eq!(recorded.label, Some("Nachtdreh".to_owned()));
    assert!(
        ports
            .shooting_day_commands
            .last_reschedule
            .lock()
            .await
            .is_none(),
        "label update must not dispatch reschedule"
    );
}

#[tokio::test]
async fn explicit_null_label_clears_label() {
    let ports = FakePorts::default();
    let sd_id = seed_shooting_day_chain(&ports).await;
    let state = AppState::new(ports.clone());
    let req = request_from_json(serde_json::json!({"version": 1, "label": null}));

    // Rename-to-null was equally inexpressible before issue #372.
    let result = update_shooting_day(State(state), dummy_user(), Path(sd_id), Json(req)).await;
    let (status, _) = result.expect("explicit null label must clear, not 422");
    assert_eq!(status, StatusCode::OK);

    let recorded = ports
        .shooting_day_commands
        .last_rename
        .lock()
        .await
        .clone()
        .expect("rename must have been dispatched");
    assert_eq!(recorded.label, None);
}

#[tokio::test]
async fn no_update_field_is_422() {
    let ports = FakePorts::default();
    let sd_id = seed_shooting_day_chain(&ports).await;
    let state = AppState::new(ports);
    let req = request_from_json(serde_json::json!({"version": 1}));

    let problem = update_shooting_day(State(state), dummy_user(), Path(sd_id), Json(req))
        .await
        .expect_err("absent date/label/order_key must be rejected")
        .into_problem();
    assert_eq!(problem.status, 422);
    assert_eq!(problem.code, "domain.validation");
    assert!(!problem.detail.is_empty());
}
