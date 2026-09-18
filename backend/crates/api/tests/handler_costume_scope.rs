// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! Costume create block-scope gate (issue #453 CodeRabbit review).
//!
//! `POST /v1/costumes` is middleware-gated on block *membership* only; the
//! handler must therefore verify INSIDE the handler body that the requested
//! repertoire `season_id` belongs to the caller's active `X-Active-Block`
//! before dispatching `CreateCostume` — otherwise a member of block A could
//! plant a repertoire row for a season of another block and expose it
//! through season-scoped costume reads. A cross-block (or unknown) season is
//! rejected as `season.not-found` (no scope oracle), and no command runs.

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
use api::handlers::{CreateCostumeRequest, create_costume};
use api::problems::Json;
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::block::views::BlockView;
use breakdown_core::shared::{AggregateVersion, BlockId, SeasonId, SeriesId};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

fn block_view(id: Uuid, season_id: SeasonId, series_id: SeriesId) -> BlockView {
    BlockView {
        id,
        season_id,
        series_id,
        number: 1,
        start_date: None,
        end_date: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

#[tokio::test]
async fn create_costume_accepts_repertoire_season_of_active_block() {
    let ports = FakePorts::default();
    let season = SeasonId::new();
    let series = SeriesId::new();
    let active_block = BlockId::new();
    ports
        .block_repo
        .blocks
        .lock()
        .await
        .insert(active_block.0, block_view(active_block.0, season, series));
    let state = AppState::new(ports);

    let result = create_costume::<FakePorts>(
        State(state),
        dummy_user(),
        api::auth::ActiveBlock(active_block),
        Json(CreateCostumeRequest {
            season_id: Some(season),
        }),
    )
    .await;

    let (status, Json(resp)) = result.expect("same-block season must be accepted");
    assert_eq!(status, StatusCode::CREATED);
    assert!(!resp.id.is_nil());
    assert_eq!(resp.version, AggregateVersion::INITIAL);
}

#[tokio::test]
async fn create_costume_rejects_cross_block_season_with_season_not_found() {
    let ports = FakePorts::default();
    let active_season = SeasonId::new();
    let other_season = SeasonId::new();
    let series = SeriesId::new();
    let active_block = BlockId::new();
    ports.block_repo.blocks.lock().await.insert(
        active_block.0,
        block_view(active_block.0, active_season, series),
    );
    let state = AppState::new(ports);

    let problem = create_costume::<FakePorts>(
        State(state),
        dummy_user(),
        api::auth::ActiveBlock(active_block),
        Json(CreateCostumeRequest {
            season_id: Some(other_season),
        }),
    )
    .await
    .expect_err("cross-block season must be rejected")
    .into_problem();

    assert_eq!(problem.status, StatusCode::NOT_FOUND);
    assert_eq!(problem.code, "season.not-found");
    assert!(!problem.detail.is_empty());
}

/// A season-less create (legacy `{}` body) dispatches without any scope
/// check — the repertoire binding is optional.
#[tokio::test]
async fn create_costume_without_season_still_dispatches() {
    let ports = FakePorts::default();
    let active_block = BlockId::new();
    let state = AppState::new(ports);

    let result = create_costume::<FakePorts>(
        State(state),
        dummy_user(),
        api::auth::ActiveBlock(active_block),
        Json(CreateCostumeRequest { season_id: None }),
    )
    .await;

    let (status, Json(resp)) = result.expect("season-less create must not be scope-checked");
    assert_eq!(status, StatusCode::CREATED);
    assert!(!resp.id.is_nil());
}
