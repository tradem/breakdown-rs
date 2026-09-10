// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Cross-aggregate uniqueness pre-checks (issue #404).
//!
//! Duplicate series numbering (season / block / episode) is rejected with a
//! clean 409 at the API edge — *before* dispatch — instead of the old
//! behavior: a 2xx whose `*Created` event becomes a permanent 23505 poison
//! event that kills the projector. The advisory pre-check rides the handler
//! (the only legitimate read-model consumer); the projection unique index
//! stays authoritative against races.
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
use api::handlers::{
    CreateBlockRequest, CreateEpisodeRequest, CreateSeasonRequest, create_block, create_episode,
    create_season,
};
use api::problems::Json;
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::block::views::BlockView;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, BlockId, SeasonId, SeriesId};
use chrono::Utc;
use common::FakePorts;
use uuid::Uuid;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

fn season_view(id: Uuid, series_id: SeriesId, number: i32) -> SeasonView {
    SeasonView {
        id,
        series_id,
        number,
        title: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

fn block_view(id: Uuid, series_id: SeriesId, number: i32) -> BlockView {
    BlockView {
        id,
        season_id: SeasonId::new(),
        series_id,
        number,
        start_date: None,
        end_date: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

fn episode_view(id: Uuid, series_id: SeriesId, number: i32) -> EpisodeView {
    EpisodeView {
        id,
        block_id: BlockId::new(),
        series_id,
        number,
        name: None,
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    }
}

// ---------------------------------------------------------------------------
// Season numbering
// ---------------------------------------------------------------------------

#[tokio::test]
async fn create_season_rejects_duplicate_series_number_with_409() {
    let ports = FakePorts::default();
    let series = SeriesId::new();
    let existing = Uuid::now_v7();
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(existing, season_view(existing, series, 1));
    let state = AppState::new(ports);

    let problem = create_season::<FakePorts>(
        State(state),
        dummy_user(),
        Json(CreateSeasonRequest {
            series_id: series,
            number: 1,
            title: None,
        }),
    )
    .await
    .expect_err("duplicate season number must be rejected at the API edge")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "season.number-already-exists");
}

#[tokio::test]
async fn create_season_allows_a_free_number() {
    let ports = FakePorts::default();
    let series = SeriesId::new();
    let existing = Uuid::now_v7();
    ports
        .season_repo
        .seasons
        .lock()
        .await
        .insert(existing, season_view(existing, series, 1));
    let state = AppState::new(ports);

    let (status, _) = create_season::<FakePorts>(
        State(state),
        dummy_user(),
        Json(CreateSeasonRequest {
            series_id: series,
            number: 2,
            title: None,
        }),
    )
    .await
    .expect("a free season number must dispatch normally");

    assert_eq!(status, StatusCode::CREATED);
}

// ---------------------------------------------------------------------------
// Block numbering
// ---------------------------------------------------------------------------

#[tokio::test]
async fn create_block_rejects_duplicate_series_number_with_409() {
    let ports = FakePorts::default();
    let series = SeriesId::new();
    let existing = Uuid::now_v7();
    ports
        .block_repo
        .blocks
        .lock()
        .await
        .insert(existing, block_view(existing, series, 1));
    let state = AppState::new(ports);

    let problem = create_block::<FakePorts>(
        State(state),
        dummy_user(),
        Json(CreateBlockRequest {
            season_id: SeasonId::new(),
            series_id: series,
            number: 1,
            start_date: None,
            end_date: None,
        }),
    )
    .await
    .expect_err("duplicate block number must be rejected at the API edge")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "block.number-already-exists");
}

#[tokio::test]
async fn create_block_allows_a_free_number() {
    let ports = FakePorts::default();
    let series = SeriesId::new();
    let existing = Uuid::now_v7();
    ports
        .block_repo
        .blocks
        .lock()
        .await
        .insert(existing, block_view(existing, series, 1));
    let state = AppState::new(ports);

    let (status, _) = create_block::<FakePorts>(
        State(state),
        dummy_user(),
        Json(CreateBlockRequest {
            season_id: SeasonId::new(),
            series_id: series,
            number: 2,
            start_date: None,
            end_date: None,
        }),
    )
    .await
    .expect("a free block number must dispatch normally");

    assert_eq!(status, StatusCode::CREATED);
}

// ---------------------------------------------------------------------------
// Episode numbering
// ---------------------------------------------------------------------------

#[tokio::test]
async fn create_episode_rejects_duplicate_series_number_with_409() {
    let ports = FakePorts::default();
    let series = SeriesId::new();
    let existing = Uuid::now_v7();
    ports
        .episode_repo
        .episodes
        .lock()
        .await
        .insert(existing, episode_view(existing, series, 1));
    let state = AppState::new(ports);

    let problem = create_episode::<FakePorts>(
        State(state),
        dummy_user(),
        Json(CreateEpisodeRequest {
            block_id: BlockId::new(),
            series_id: series,
            number: 1,
            name: None,
        }),
    )
    .await
    .expect_err("duplicate episode number must be rejected at the API edge")
    .into_problem();

    assert_eq!(problem.status, 409);
    assert_eq!(problem.code, "episode.number-already-exists");
}

#[tokio::test]
async fn create_episode_allows_a_free_number() {
    let ports = FakePorts::default();
    let series = SeriesId::new();
    let existing = Uuid::now_v7();
    ports
        .episode_repo
        .episodes
        .lock()
        .await
        .insert(existing, episode_view(existing, series, 1));
    let state = AppState::new(ports);

    let (status, _) = create_episode::<FakePorts>(
        State(state),
        dummy_user(),
        Json(CreateEpisodeRequest {
            block_id: BlockId::new(),
            series_id: series,
            number: 2,
            name: None,
        }),
    )
    .await
    .expect("a free episode number must dispatch normally");

    assert_eq!(status, StatusCode::CREATED);
}
