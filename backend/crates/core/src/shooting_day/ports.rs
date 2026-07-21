// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Ports for the `ShootingDay` aggregate (command dispatch + read model).

use crate::error::DomainError;
use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, EpisodeId, ShootingDayId};

use super::commands::{
    ArchiveShootingDay, CreateShootingDay, RenameShootingDay, ReorderShootingDay,
    RescheduleShootingDay,
};
use super::views::ShootingDayView;

/// Async write port for the `ShootingDayAggregate`. Mockable seam used by API handlers.
#[allow(async_fn_in_trait)]
pub trait ShootingDayCommands: Send + Sync {
    /// Create a new shooting-day aggregate. Returns the id and the initial
    /// aggregate version (`AggregateVersion::INITIAL`).
    async fn create(
        &self,
        cmd: CreateShootingDay,
    ) -> Result<(ShootingDayId, AggregateVersion), DomainError>;

    /// Rename a shooting day.
    async fn rename(&self, cmd: RenameShootingDay) -> Result<AggregateVersion, DomainError>;

    /// (Re)schedule a shooting day; `None` unschedules it.
    async fn reschedule(&self, cmd: RescheduleShootingDay)
    -> Result<AggregateVersion, DomainError>;

    /// Reorder a shooting day to a new `order_key`.
    async fn reorder(&self, cmd: ReorderShootingDay) -> Result<AggregateVersion, DomainError>;

    /// Soft-archive a shooting day (terminal).
    async fn archive(&self, cmd: ArchiveShootingDay) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `ShootingDayView` projections.
#[allow(async_fn_in_trait)]
pub trait ShootingDayRepository: Send + Sync {
    /// Fetch a single shooting day by id (including archived).
    async fn find_by_id(&self, id: ShootingDayId) -> Result<ShootingDayView, DomainError>;

    /// List the non-archived shooting days of an episode ordered by `order_key ASC`.
    ///
    /// Archived days are intentionally excluded so this query can serve the
    /// scheduling picker without leaking hidden entries.
    async fn list_by_episode(
        &self,
        episode_id: EpisodeId,
    ) -> Result<Vec<ShootingDayView>, DomainError>;

    /// Reverse query: all scenes filming on a given ShootingDay, joined via
    /// `projection_scene_shooting_day`.
    async fn scenes_by_shooting_day(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<Vec<SceneView>, DomainError>;
}
