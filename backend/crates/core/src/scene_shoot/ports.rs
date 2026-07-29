// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Hexagonal ports for the SceneShoot context.
//!
//! `SceneShootCommands` is the **write** seam (command-in) and
//! `SceneShootRepository` is the **read** seam (flat views-out). No
//! event-store abstraction leaks into `core`; persistence is owned by the
//! `kameo_es` adapter in `infra`.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SceneShootId, ShootingDayId, UserId};

use super::commands::{
    AddSceneShootNote, FinishSceneShoot, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote,
};
use super::views::{DispoRow, SceneShootView, ShootDayRow, SollIstReport};

/// Async write port for the `SceneShootAggregate`. Mockable seam used by API handlers.
#[allow(async_fn_in_trait)]
pub trait SceneShootCommands: Send + Sync {
    /// Plan a new scene shoot. Returns the id and the initial aggregate version.
    async fn plan(
        &self,
        actor: UserId, cmd: PlanSceneShoot,
    ) -> Result<(SceneShootId, AggregateVersion), DomainError>;

    /// Replan (reorder) an existing scene shoot's planned order.
    async fn replan(&self, actor: UserId, cmd: ReplanSceneShoot) -> Result<AggregateVersion, DomainError>;

    /// Start execution of this scene shoot.
    async fn start(&self, actor: UserId, cmd: StartSceneShoot) -> Result<AggregateVersion, DomainError>;

    /// Set the actual (Ist) execution order for this scene shoot.
    async fn set_actual_order(&self, actor: UserId, cmd: SetActualOrder) -> Result<AggregateVersion, DomainError>;

    /// Finish a scene shoot (mark as Shot).
    async fn finish(&self, actor: UserId, cmd: FinishSceneShoot) -> Result<AggregateVersion, DomainError>;

    /// Skip a scene shoot (mark as Skipped).
    async fn skip(&self, actor: UserId, cmd: SkipSceneShoot) -> Result<AggregateVersion, DomainError>;

    /// Add a mutable, audited note to this scene shoot.
    async fn add_note(&self, actor: UserId, cmd: AddSceneShootNote) -> Result<AggregateVersion, DomainError>;

    /// Update the body of an existing note.
    async fn update_note(&self, actor: UserId, cmd: UpdateSceneShootNote)
    -> Result<AggregateVersion, DomainError>;

    /// Remove a note from this scene shoot.
    async fn remove_note(&self, actor: UserId, cmd: RemoveSceneShootNote)
    -> Result<AggregateVersion, DomainError>;

    /// Link a continuity photo to this scene shoot.
    async fn link_continuity_photo(
        &self,
        actor: UserId, cmd: LinkContinuityPhoto,
    ) -> Result<AggregateVersion, DomainError>;

    /// Unlink a continuity photo from this scene shoot.
    async fn unlink_continuity_photo(
        &self,
        actor: UserId, cmd: UnlinkContinuityPhoto,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `SceneShootView` projections.
#[allow(async_fn_in_trait)]
pub trait SceneShootRepository: Send + Sync {
    /// Fetch a single scene shoot by id.
    async fn find_by_id(&self, id: SceneShootId) -> Result<SceneShootView, DomainError>;

    /// List all scene shoots for a given shooting day.
    async fn list_by_shooting_day(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> Result<Vec<SceneShootView>, DomainError>;

    /// Find a scene shoot by (scene_id, shooting_day_id) pair.
    async fn find_by_scene_and_day(
        &self,
        scene_id: Uuid,
        shooting_day_id: ShootingDayId,
    ) -> Result<SceneShootView, DomainError>;

    /// List all scene shoots (across all days) for a given scene.
    async fn list_by_scene(&self, scene_id: Uuid) -> Result<Vec<SceneShootView>, DomainError>;
}

/// Read port for the three shoot-day reports.
///
/// Futures are explicitly `Send` so background workers (report archival) can
/// await them on multi-threaded runtimes. RPITIT `async fn` alone does not
/// imply `Send`.
pub trait SceneShootReportRepository: Send + Sync {
    /// Dispo (planned / Soll): scenes ordered by `planned_order ASC`.
    fn dispo_report(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> impl std::future::Future<Output = Result<Vec<DispoRow>, DomainError>> + Send;

    /// Shoot Day (actual / Ist): scenes ordered by `actual_order ASC NULLS LAST`.
    fn shoot_day_report(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> impl std::future::Future<Output = Result<Vec<ShootDayRow>, DomainError>> + Send;

    /// Soll-Ist-Vergleich: planned vs actual diff with flags.
    fn soll_ist_report(
        &self,
        shooting_day_id: ShootingDayId,
    ) -> impl std::future::Future<Output = Result<SollIstReport, DomainError>> + Send;
}
