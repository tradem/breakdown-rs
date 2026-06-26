// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Scene context.
//!
//! `SceneCommands` is the **write** seam (command-in) and `SceneRepository` is the
//! **read** seam (flat views-out). No event-store abstraction leaks into `core`;
//! persistence is owned by the `kameo_es` adapter in `infra`.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, ProjectId};

use super::commands::{AssignCharacter, CreateScene, RemoveCharacter, UpdateSceneDetails};
use super::views::SceneView;

/// Async write port for the `SceneAggregate`. Mockable seam used by API handlers.
#[allow(async_fn_in_trait)]
pub trait SceneCommands: Send + Sync {
    /// Create a new scene aggregate. Returns the generated UUIDv7 id and the
    /// initial aggregate version (`AggregateVersion::INITIAL`).
    async fn create(&self, cmd: CreateScene) -> Result<(Uuid, AggregateVersion), DomainError>;

    /// Update scene scheduling/location/mood details. The command's `version`
    /// is used for optimistic concurrency.
    async fn update_details(
        &self,
        cmd: UpdateSceneDetails,
    ) -> Result<AggregateVersion, DomainError>;

    /// Assign a character to the scene.
    async fn assign_character(&self, cmd: AssignCharacter)
    -> Result<AggregateVersion, DomainError>;

    /// Remove a character from the scene.
    async fn remove_character(&self, cmd: RemoveCharacter)
    -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `SceneView` projections.
#[allow(async_fn_in_trait)]
pub trait SceneRepository: Send + Sync {
    /// Fetch a single scene by id.
    async fn find_by_id(&self, id: Uuid) -> Result<SceneView, DomainError>;

    /// Paginated list of scenes inside a project.
    async fn list_by_project(
        &self,
        project_id: ProjectId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SceneView>, DomainError>;

    /// Cross-context convenience read: all scenes that feature a character.
    /// Implemented as a JOIN between `projection_scene_character` and `projection_scene`.
    async fn scenes_by_character(&self, character_id: Uuid) -> Result<Vec<SceneView>, DomainError>;
}
