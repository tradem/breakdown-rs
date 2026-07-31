// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Commands for the `SceneShoot` aggregate.

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SeriesId, ShootingDayId, UserId,
};

/// Plan a new `SceneShoot` for the given (scene, shooting_day) pair.
///
/// The pair uniqueness invariant is enforced at the aggregate level: a second
/// `PlanSceneShoot` for an existing non-empty `(scene_id, shooting_day_id)`
/// pair is rejected with `PairAlreadyExists`.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct PlanSceneShoot {
    pub id: SceneShootId,
    pub scene_id: Uuid,
    pub shooting_day_id: ShootingDayId,
    pub series_id: Option<SeriesId>,
    pub planned_order: LexicalSortKey,
}

/// Replan an existing `SceneShoot` with a new `planned_order`.
///
/// Rejected with `PlannedOrderFrozen` if execution data has been recorded
/// (`actual_order` or `start_dt` is set).
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ReplanSceneShoot {
    pub id: SceneShootId,
    pub planned_order: LexicalSortKey,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Start execution of this scene shoot. Records the start timestamp.
///
/// Idempotent: re-dispatching with the same `start_dt` is a no-op.
/// Rejected with `AlreadyStarted` if already started with a different value.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct StartSceneShoot {
    pub id: SceneShootId,
    pub start_dt: DateTime<Utc>,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Set (or replace) the actual (Ist) execution order for this scene shoot.
///
/// Setting `actual_order` also freezes `planned_order` and transitions
/// status to `InProgress` if it was `Planned`/`Scheduled`.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct SetActualOrder {
    pub id: SceneShootId,
    pub actual_order: LexicalSortKey,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Finish this scene shoot. Records the end timestamp and transitions to `Shot`.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct FinishSceneShoot {
    pub id: SceneShootId,
    pub end_dt: DateTime<Utc>,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Skip this scene shoot. Transitions to `Skipped`.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct SkipSceneShoot {
    pub id: SceneShootId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Add an audited note to this scene shoot.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct AddSceneShootNote {
    pub id: SceneShootId,
    pub note_id: Uuid,
    pub body: String,
    pub series_id: Option<SeriesId>,
    pub author: Option<UserId>,
}

/// Update the body of an existing note on this scene shoot.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UpdateSceneShootNote {
    pub id: SceneShootId,
    pub note_id: Uuid,
    pub body: String,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Remove a note from this scene shoot.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RemoveSceneShootNote {
    pub id: SceneShootId,
    pub note_id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Link a continuity photo to this scene shoot.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct LinkContinuityPhoto {
    pub id: SceneShootId,
    pub photo_id: PhotoId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Unlink a continuity photo from this scene shoot.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// scene-shoot projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct UnlinkContinuityPhoto {
    pub id: SceneShootId,
    pub photo_id: PhotoId,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for PlanSceneShoot {
    fn command_name() -> &'static str {
        "PlanSceneShoot"
    }
}
impl kameo_es::CommandName for ReplanSceneShoot {
    fn command_name() -> &'static str {
        "ReplanSceneShoot"
    }
}
impl kameo_es::CommandName for StartSceneShoot {
    fn command_name() -> &'static str {
        "StartSceneShoot"
    }
}
impl kameo_es::CommandName for SetActualOrder {
    fn command_name() -> &'static str {
        "SetActualOrder"
    }
}
impl kameo_es::CommandName for FinishSceneShoot {
    fn command_name() -> &'static str {
        "FinishSceneShoot"
    }
}
impl kameo_es::CommandName for SkipSceneShoot {
    fn command_name() -> &'static str {
        "SkipSceneShoot"
    }
}
impl kameo_es::CommandName for AddSceneShootNote {
    fn command_name() -> &'static str {
        "AddSceneShootNote"
    }
}
impl kameo_es::CommandName for UpdateSceneShootNote {
    fn command_name() -> &'static str {
        "UpdateSceneShootNote"
    }
}
impl kameo_es::CommandName for RemoveSceneShootNote {
    fn command_name() -> &'static str {
        "RemoveSceneShootNote"
    }
}
impl kameo_es::CommandName for LinkContinuityPhoto {
    fn command_name() -> &'static str {
        "LinkContinuityPhoto"
    }
}
impl kameo_es::CommandName for UnlinkContinuityPhoto {
    fn command_name() -> &'static str {
        "UnlinkContinuityPhoto"
    }
}
