// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Handler tests for the per-character appearances route (issue #621):
//! `GET /v1/characters/{id}/appearances`.
//!
//! The route is classified `Authenticated` at the middleware and gated
//! handler-internally on an active costume-department role in the character's
//! season (`// AUTHZ-GATE:`). This file pins the HTTP surface — 200 shape,
//! `404` for an unknown id (the fake emits the generic `domain.not-found`;
//! production emits `character.not-found`), and the `403` denial — while
//! the real SQL ordering / costume binding is covered against Postgres in
//! `crates/integration-tests/tests/character_appearances_query.rs`.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

use crate::common;

use axum::extract::State;
use axum::http::StatusCode;
use uuid::Uuid;

use api::auth::CurrentUser;
use api::handlers::get_character_appearances;
use api::problems::{Json, Path};
use api::state::AppState;
use breakdown_core::character::views::{
    AppearanceCostumeView, CharacterAppearanceView, CharacterView,
};
use breakdown_core::character::{CharacterCategory, CharacterMeasurements, ContactInfo};
use breakdown_core::membership::Role;
use breakdown_core::shared::{AggregateVersion, BlockId, EpisodeId, ProjectId, SeasonId, UserId};
use common::FakePorts;

const USER: &str = "test-user";

fn dummy_user() -> CurrentUser {
    CurrentUser::dummy(USER)
}

async fn seed_character(ports: &FakePorts, character_id: Uuid, season_id: SeasonId) {
    ports.character_repo.characters.lock().await.insert(
        character_id,
        CharacterView {
            id: character_id,
            season_id,
            name: "Held".into(),
            category: CharacterCategory::MainCast,
            measurements: CharacterMeasurements::default(),
            contact: ContactInfo::default(),
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        },
    );
}

/// Grant the caller an active costume role in `season_id` (the handler's
/// `has_active_costume_role_in_season` predicate).
async fn grant_costume_role(ports: &FakePorts, season_id: SeasonId) {
    ports
        .membership_repo
        .seed_active(
            BlockId::new(),
            UserId::from_sub(USER),
            Role::CostumeDesigner,
            season_id,
            ProjectId::new(),
        )
        .await;
}

fn appearance(scene_id: Uuid, number: u32, costume_id: Uuid) -> CharacterAppearanceView {
    CharacterAppearanceView {
        scene_id,
        episode_id: EpisodeId::new(),
        scene_number: Some(number),
        synopsis: Some(format!("Szene {number}")),
        costumes: vec![AppearanceCostumeView {
            costume_id,
            costume_category_id: None,
            costume_category_name: Some("Oberteil".into()),
            order: 0,
            note: None,
        }],
    }
}

#[tokio::test]
async fn appearances_returns_200_with_the_seeded_rows() {
    let ports = FakePorts::default();
    let season_id = SeasonId::new();
    let character_id = Uuid::now_v7();
    seed_character(&ports, character_id, season_id).await;
    grant_costume_role(&ports, season_id).await;

    let rows = vec![
        appearance(Uuid::now_v7(), 10, Uuid::now_v7()),
        appearance(Uuid::now_v7(), 20, Uuid::now_v7()),
    ];
    ports
        .character_repo
        .appearances
        .lock()
        .await
        .insert(character_id, rows.clone());
    let state = AppState::new(ports);

    let (status, Json(body)) =
        get_character_appearances::<FakePorts>(State(state), dummy_user(), Path(character_id))
            .await
            .expect("authorized caller must succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.len(), 2);
    assert_eq!(body[0].scene_number, Some(10));
    assert_eq!(body[0].costumes.len(), 1);
    assert_eq!(
        body[0].costumes[0].costume_id,
        rows[0].costumes[0].costume_id
    );
}

#[tokio::test]
async fn appearances_unknown_character_is_404() {
    let ports = FakePorts::default();
    let state = AppState::new(ports);

    let problem =
        get_character_appearances::<FakePorts>(State(state), dummy_user(), Path(Uuid::now_v7()))
            .await
            .expect_err("unknown character must not resolve")
            .into_problem();

    assert_eq!(problem.status, 404);
    // The shared fake resolves a missing character to the generic code
    // (`domain.not-found`); production answers `character.not-found`.
    assert_eq!(problem.code, "domain.not-found");
}

#[tokio::test]
async fn appearances_without_a_costume_role_is_403() {
    // The character exists, but the caller holds no active costume role in its
    // season — the handler-internal gate must deny before reading appearances.
    let ports = FakePorts::default();
    let character_id = Uuid::now_v7();
    seed_character(&ports, character_id, SeasonId::new()).await;
    let state = AppState::new(ports);

    let problem =
        get_character_appearances::<FakePorts>(State(state), dummy_user(), Path(character_id))
            .await
            .expect_err("caller without a costume role must be denied")
            .into_problem();

    assert_eq!(problem.status, 403);
}

#[tokio::test]
async fn appearances_with_a_non_costume_role_is_403() {
    // A block member with a non-costume role (e.g. an ops admin) does not
    // satisfy the costume-department predicate.
    let ports = FakePorts::default();
    let season_id = SeasonId::new();
    let character_id = Uuid::now_v7();
    seed_character(&ports, character_id, season_id).await;
    ports
        .membership_repo
        .seed_active(
            BlockId::new(),
            UserId::from_sub(USER),
            Role::OpsAdmin,
            season_id,
            ProjectId::new(),
        )
        .await;
    let state = AppState::new(ports);

    let problem =
        get_character_appearances::<FakePorts>(State(state), dummy_user(), Path(character_id))
            .await
            .expect_err("a non-costume role must be denied")
            .into_problem();

    assert_eq!(problem.status, 403);
}
