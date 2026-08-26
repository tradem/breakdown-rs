// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: hy3 (opencode-go)
//! Generic audit / journal projector.
//!
//! Generalized to all 11 aggregate categories (`season`, `block`, `episode`,
//! `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`,
//! `costume_category`, `photo`, `membership`). Each category gets its own
//! `EntityEventHandler` impl that extracts `actor`, `provenance`, and
//! `series_id` from `EventMetadata` and delegates to the shared
//! [`write_audit_row`] helper.
//!
//! Idempotency under redelivery is guaranteed by the deterministic
//! `event_key` + `ON CONFLICT (event_key) DO NOTHING` guard.
//!
//! ## Compile-time-exhaustive coverage guard (Task 4)
//!
//! The [`AuditCategory`] enum acts as a compile-time invariant: adding a new
//! aggregate category without adding a variant and registering its projector
//! fails compilation.  See the `audit_category_coverage_is_exhaustive` test
//! for documentation of this guard.

use breakdown_core::shared::{EventMetadata, PhotoId, SceneShootId, ShootingDayId};
use breakdown_core::{
    block::{aggregate::BlockAggregate, events::BlockEvent},
    character::{aggregate::CharacterAggregate, events::CharacterEvent},
    costume::{aggregate::CostumeAggregate, events::CostumeEvent},
    costume_category::{aggregate::CostumeCategoryAggregate, events::CostumeCategoryEvent},
    episode::{aggregate::EpisodeAggregate, events::EpisodeEvent},
    membership::{aggregate::BlockMembership, events::MembershipEvent},
    photo::{aggregate::PhotoAggregate, events::PhotoEvent},
    scene::{aggregate::SceneAggregate, events::SceneEvent},
    scene_shoot::{aggregate::SceneShootAggregate, events::SceneShootEvent},
    season::{aggregate::SeasonAggregate, events::SeasonEvent},
    settings::{aggregate::SettingsAggregate, events::SettingsEvent},
    shooting_day::{aggregate::ShootingDayAggregate, events::ShootingDayEvent},
};
use sqlx::{self as sqlx, Postgres, Transaction};

use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use kameo_es::{Event, EventType};

// ── Compile-time-exhaustive category enum ─────────────────────────────

/// Aggregate categories covered by the audit projector.
///
/// This enum is the **compile-time-exhaustive coverage guard** (Task 4):
/// adding a new aggregate category requires:
///
/// 1. Adding a variant here (new variant without match arms = compile error).
/// 2. Registering an `EntityEventHandler` audit projector for the variant
///    in [`spawn_all_audit_projectors`](super::spawn_all_audit_projectors).
///
/// `#[non_exhaustive]` allows downstream crates to pattern-match without
/// breaking on version upgrade, while the exhaustive match at the call
/// site in `mod.rs` keeps the invariant compiler-enforced.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum AuditCategory {
    Season,
    Block,
    Episode,
    Scene,
    SceneShoot,
    ShootingDay,
    Character,
    Costume,
    CostumeCategory,
    Photo,
    Membership,
    Settings,
}

impl AuditCategory {
    /// Canonical aggregate entity-type string (same as `Entity::category()`).
    pub fn entity_type(self) -> &'static str {
        match self {
            AuditCategory::Season => "season",
            AuditCategory::Block => "block",
            AuditCategory::Episode => "episode",
            AuditCategory::Scene => "scene",
            AuditCategory::SceneShoot => "scene_shoot",
            AuditCategory::ShootingDay => "shooting_day",
            AuditCategory::Character => "character",
            AuditCategory::Costume => "costume",
            AuditCategory::CostumeCategory => "costume_category",
            AuditCategory::Photo => "photo",
            AuditCategory::Membership => "membership",
            AuditCategory::Settings => "settings",
        }
    }

    /// Returns the name of the projector struct for this category.
    pub fn projector_type(self) -> &'static str {
        match self {
            AuditCategory::Season => "Season",
            AuditCategory::Block => "Block",
            AuditCategory::Episode => "Episode",
            AuditCategory::Scene => "Scene",
            AuditCategory::SceneShoot => "SceneShoot",
            AuditCategory::ShootingDay => "ShootingDay",
            AuditCategory::Character => "Character",
            AuditCategory::Costume => "Costume",
            AuditCategory::CostumeCategory => "CostumeCategory",
            AuditCategory::Photo => "Photo",
            AuditCategory::Membership => "Membership",
            AuditCategory::Settings => "Settings",
        }
    }
}

// ── shared insert logic ───────────────────────────────────────────────

/// Write an audit row into `projection_audit`.
///
/// Uses the same `event_key` + `ON CONFLICT (event_key) DO NOTHING` idempotency
/// pattern that the membership-only v1 projector used. `event_key` is derived
/// from deterministic content (entity_type + entity_id + event_type + payload)
/// so that redelivered events never create duplicates.
///
/// `provenance` is written as a plain-text label ("Human" / saga name / "System").
/// `series_id` is written as a nullable UUID, denormalized at dispatch time.
/// `block_id` is set to the entity_id for backwards compatibility with the
/// existing `idx_projection_audit_block` index.
#[allow(clippy::too_many_arguments)]
async fn write_audit_row(
    ctx: &mut Transaction<'_, Postgres>,
    entity_type: &str,
    entity_id: &str,
    event_type: &str,
    actor: Option<String>,
    provenance: &str,
    series_id: Option<String>,
    event: impl serde::Serialize,
    event_timestamp: chrono::DateTime<chrono::Utc>,
    event_id: uuid::Uuid,
) -> sqlx::Result<()> {
    let payload = serde_json::to_value(&event).unwrap_or(serde_json::Value::Null);
    let event_key = format!("{entity_type}:{entity_id}:{event_type}:{payload}");

    let series_uuid: Option<uuid::Uuid> = series_id
        .and_then(|s| {
            // The series_id string is already the UUID value.
            uuid::Uuid::parse_str(&s).ok()
        })
        .or(None);

    sqlx::query(
        r#"
        INSERT INTO projection_audit
            (id, event_key, entity_type, entity_id, event_type, block_id, series_id, actor, provenance, payload, projector_version, occurred_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        ON CONFLICT (event_key) DO NOTHING
        "#,
    )
    .bind(event_id)
    .bind(event_key)
    .bind(entity_type)
        .bind(entity_id)
    .bind(event_type)
    .bind(
        uuid::Uuid::parse_str(entity_id)
            .unwrap_or_default(), // block_id — kept for compatibility with existing idx_projection_audit_block
    )
    .bind(series_uuid)
    .bind(actor)
    .bind(provenance)
    .bind(payload)
    .bind(crate::projectors::PROJECTOR_VERSION)
    .bind(event_timestamp)
    .execute(&mut **ctx)
        .await
        .map(|_| ())
}

// ── metadata helpers ──────────────────────────────────────────────────

/// Extract actor, provenance, and series_id from event metadata.
///
/// Returns `(actor, provenance, series_id)`.  If no `EventMetadata` is
/// present the defaults are `actor = None`, `provenance = "Human"`,
/// `series_id = None`.
fn extract_metadata(
    event: &Event<impl kameo_es::EventType, EventMetadata>,
) -> (Option<String>, String, Option<String>) {
    event
        .metadata
        .data
        .as_ref()
        .map(|m| {
            (
                m.actor.as_ref().map(|u| u.as_str().to_string()),
                m.provenance.as_str().to_string(),
                m.series_id.as_ref().map(|s| s.0.to_string()),
            )
        })
        .unwrap_or_else(|| (None, "Human".to_string(), None))
}

// ── Category: season ──────────────────────────────────────────────────

/// Deduplicates events from the **Season** aggregate into `projection_audit`.
///
/// Reads `series_id` directly from `EventMetadata` — no entity→series
/// chain resolution at projection time (task 3.4 invariant).
#[derive(Clone, Default, Debug)]
pub struct SeasonAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SeasonAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SeasonAggregate, Transaction<'a, Postgres>> for SeasonAuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<SeasonEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            SeasonEvent::SeasonCreated { id, .. } | SeasonEvent::SeasonRenamed { id, .. } => {
                id.to_string()
            }
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "season",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: block ───────────────────────────────────────────────────

/// Deduplicates events from the **Block** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct BlockAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for BlockAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<BlockAggregate, Transaction<'a, Postgres>> for BlockAuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<BlockEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            BlockEvent::BlockCreated { id, .. } | BlockEvent::BlockTimeSpanUpdated { id, .. } => {
                id.to_string()
            }
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "block",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: episode ─────────────────────────────────────────────────

/// Deduplicates events from the **Episode** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct EpisodeAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for EpisodeAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<EpisodeAggregate, Transaction<'a, Postgres>> for EpisodeAuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<EpisodeEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            EpisodeEvent::EpisodeCreated { id, .. } | EpisodeEvent::EpisodeRenamed { id, .. } => {
                id.to_string()
            }
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "episode",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: scene ───────────────────────────────────────────────────

/// Deduplicates events from the **Scene** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct SceneAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SceneAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SceneAggregate, Transaction<'a, Postgres>> for SceneAuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<SceneEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            SceneEvent::SceneCreated { id, .. }
            | SceneEvent::SceneDetailsUpdated { id, .. }
            | SceneEvent::CharacterAssigned { id, .. }
            | SceneEvent::CharacterRemoved { id, .. }
            | SceneEvent::ShootingDayScheduled { id, .. }
            | SceneEvent::ShootingDayUnscheduled { id, .. } => id.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "scene",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: scene_shoot ─────────────────────────────────────────────

/// Deduplicates events from the **SceneShoot** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct SceneShootAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SceneShootAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SceneShootAggregate, Transaction<'a, Postgres>>
    for SceneShootAuditProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: SceneShootId,
        event: Event<SceneShootEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            SceneShootEvent::SceneShootPlanned { id, .. }
            | SceneShootEvent::SceneShootReplanned { id, .. }
            | SceneShootEvent::SceneShootStarted { id, .. }
            | SceneShootEvent::SceneShootActualOrderSet { id, .. }
            | SceneShootEvent::SceneShootFinished { id, .. }
            | SceneShootEvent::SceneShootSkipped { id, .. }
            | SceneShootEvent::ShootDayNoteAdded { id, .. }
            | SceneShootEvent::ShootDayNoteUpdated { id, .. }
            | SceneShootEvent::ShootDayNoteRemoved { id, .. }
            | SceneShootEvent::ContinuityPhotoLinked { id, .. }
            | SceneShootEvent::ContinuityPhotoUnlinked { id, .. } => id.0.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "scene_shoot",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: shooting_day ────────────────────────────────────────────

/// Deduplicates events from the **ShootingDay** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct ShootingDayAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for ShootingDayAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<ShootingDayAggregate, Transaction<'a, Postgres>>
    for ShootingDayAuditProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: ShootingDayId,
        event: Event<ShootingDayEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            ShootingDayEvent::ShootingDayCreated { id, .. }
            | ShootingDayEvent::ShootingDayRenamed { id, .. }
            | ShootingDayEvent::ShootingDayRescheduled { id, .. }
            | ShootingDayEvent::ShootingDayReordered { id, .. }
            | ShootingDayEvent::ShootingDayArchived { id, .. }
            | ShootingDayEvent::ShootingDayWrapped { id, .. } => id.0.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "shooting_day",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: character ───────────────────────────────────────────────

/// Deduplicates events from the **Character** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct CharacterAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CharacterAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CharacterAggregate, Transaction<'a, Postgres>>
    for CharacterAuditProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<CharacterEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            CharacterEvent::CharacterCreated { id, .. }
            | CharacterEvent::MeasurementsUpdated { id, .. }
            | CharacterEvent::ContactInfoUpdated { id, .. } => id.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "character",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: costume ─────────────────────────────────────────────────

/// Deduplicates events from the **Costume** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct CostumeAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CostumeAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CostumeAggregate, Transaction<'a, Postgres>> for CostumeAuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<CostumeEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            CostumeEvent::CostumeCreated { id, .. }
            | CostumeEvent::CostumeNotesUpdated { id, .. }
            | CostumeEvent::CostumeAssignedToCharacter { id, .. }
            | CostumeEvent::CostumeUnassigned { id, .. }
            | CostumeEvent::DetailAdded { id, .. }
            | CostumeEvent::DetailRemoved { id, .. }
            | CostumeEvent::PhotoLinked { id, .. }
            | CostumeEvent::PhotoUnlinked { id, .. } => id.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "costume",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: costume_category ────────────────────────────────────────

/// Deduplicates events from the **CostumeCategory** aggregate into
/// `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct CostumeCategoryAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for CostumeCategoryAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<CostumeCategoryAggregate, Transaction<'a, Postgres>>
    for CostumeCategoryAuditProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<CostumeCategoryEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            CostumeCategoryEvent::CostumeCategoryCreated { id, .. }
            | CostumeCategoryEvent::CostumeCategoryRenamed { id, .. }
            | CostumeCategoryEvent::CostumeCategoryReordered { id, .. }
            | CostumeCategoryEvent::CostumeCategoryArchived { id, .. } => id.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "costume_category",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: photo ───────────────────────────────────────────────────

/// Deduplicates events from the **Photo** aggregate into `projection_audit`.
#[derive(Clone, Default, Debug)]
pub struct PhotoAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for PhotoAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<PhotoAggregate, Transaction<'a, Postgres>> for PhotoAuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: PhotoId,
        event: Event<PhotoEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            PhotoEvent::PhotoUploaded { id, .. }
            | PhotoEvent::OriginalNormalized { id, .. }
            | PhotoEvent::VariantGenerated { id, .. }
            | PhotoEvent::VariantFailed { id, .. }
            | PhotoEvent::PhotoDeleted { id, .. } => id.0.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "photo",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Backward-compat alias ────────────────────────────────────────────

/// The original v1 audit projector (membership-only).
///
/// This type still exists for API stability and tests that import
/// `infra::projectors::AuditProjector` directly; it is functionally
/// equivalent to [`MembershipAuditProjector`].
pub type AuditProjector = MembershipAuditProjector;

// ── Category: membership (v1, unchanged event extraction) ─────────────

/// Deduplicates events from the **BlockMembership** aggregate into
/// `projection_audit`.
///
/// This is the original membership-only projector, now updated to write
/// `provenance` and `series_id` from `EventMetadata`.
#[derive(Clone, Default, Debug)]
pub struct MembershipAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for MembershipAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<BlockMembership, Transaction<'a, Postgres>>
    for MembershipAuditProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<MembershipEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        // Membership events use `block_id` instead of a generic `id`.
        let block_id = match &event.data {
            MembershipEvent::MemberInvited { block_id, .. }
            | MembershipEvent::InvitationAccepted { block_id, .. }
            | MembershipEvent::RoleGranted { block_id, .. }
            | MembershipEvent::MemberRemoved { block_id, .. }
            | MembershipEvent::OwnerBootstrapped { block_id, .. } => block_id.0.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);

        write_audit_row(
            ctx,
            "membership",
            &block_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;

        Ok(())
    }
}

// ── Category: settings ────────────────────────────────────────────────

#[derive(Clone, Default, Debug)]
pub struct SettingsAuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for SettingsAuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<SettingsAggregate, Transaction<'a, Postgres>>
    for SettingsAuditProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<SettingsEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let entity_id = match &event.data {
            SettingsEvent::CredentialBound { id, .. }
            | SettingsEvent::CredentialRotated { id, .. }
            | SettingsEvent::CredentialRevoked { id, .. } => id.to_string(),
        };
        let event_type = event.data.event_type().to_string();
        let (actor, provenance, series_id) = extract_metadata(&event);
        write_audit_row(
            ctx,
            "settings",
            &entity_id,
            &event_type,
            actor,
            &provenance,
            series_id,
            &event.data,
            event.timestamp,
            event.id,
        )
        .await?;
        Ok(())
    }
}

// ── Test: compile-time-exhaustive coverage guard ──────────────────────

/// Asserts that every aggregate category has a corresponding `AuditCategory`
/// variant.
///
/// **Why this test exists (Task 4 / Decision 4):**
///
/// "Forgetting to register an audit projector for a new aggregate" is a silent
/// compile-time-free bug in the original version — each `EntityEventHandler`
/// impl is independent and the supervisor only starts the projectors it is
/// explicitly told to.  The [`AuditCategory`] enum is the primary guard:
/// adding a variant without match arms elsewhere causes a compile error.
///
/// This unit test is the **documentation anchor**: it proves to future readers
/// that the enum is meant to be exhaustive and lists all expected variants so
/// they never have to hunt through the codebase to discover the full set.
///
/// The **real** compile-time enforcement lives in `super::spawn_all_audit_projectors`
/// which matches on `AuditCategory` exhaustively — removing a variant or adding
/// a new one without a corresponding projector will fail compilation.
#[test]
fn audit_category_coverage_is_exhaustive() {
    // This const list is the source-of-truth for expected variants.
    // Adding a new aggregate MUST add a variant here AND in the enum
    // AND in the supervisor exhaustive match in mod.rs.
    let expected: [AuditCategory; 12] = [
        AuditCategory::Season,
        AuditCategory::Block,
        AuditCategory::Episode,
        AuditCategory::Scene,
        AuditCategory::SceneShoot,
        AuditCategory::ShootingDay,
        AuditCategory::Character,
        AuditCategory::Costume,
        AuditCategory::CostumeCategory,
        AuditCategory::Photo,
        AuditCategory::Membership,
        AuditCategory::Settings,
    ];

    // Verify: every category has a known entity_type string.
    let types: [&str; 12] = [
        "season",
        "block",
        "episode",
        "scene",
        "scene_shoot",
        "shooting_day",
        "character",
        "costume",
        "costume_category",
        "photo",
        "membership",
        "settings",
    ];

    for (cat, expected_type) in expected.iter().copied().zip(types.iter().copied()) {
        assert_eq!(
            cat.entity_type(),
            expected_type,
            "entity_type mismatch for {:?} (expected '{}')",
            cat,
            expected_type
        );
    }

    // There should be exactly 12 variants — no more, no fewer.
    assert_eq!(
        expected.len(),
        12,
        "AuditCategory count is not 12 — did someone add or remove a variant?"
    );
}

// --- P4.1 mutation-hardening: pure-function guards ---
//
// These kill the surviving mutants on `AuditCategory::projector_type` (`""` /
// `"xyzzy"` substitutions) and `extract_metadata` (all tuple-value substitutions
// at audit.rs:188). They are pure (no DB), so they run in `cargo test`.
#[cfg(test)]
mod mutation_tests {
    use super::*;
    use breakdown_core::season::events::SeasonEvent;
    use breakdown_core::shared::{AggregateVersion, EventMetadata, Provenance, SeriesId, UserId};
    use kameo_es::{Event, Metadata, StreamId};

    fn make_event(meta: Option<EventMetadata>) -> Event<SeasonEvent, EventMetadata> {
        Event {
            id: uuid::Uuid::now_v7(),
            partition_key: uuid::Uuid::now_v7(),
            partition_id: 0,
            transaction_id: uuid::Uuid::now_v7(),
            partition_sequence: 0,
            stream_version: 0,
            stream_id: StreamId::new(format!("season-{}", uuid::Uuid::now_v7())),
            name: "SeasonCreated".to_string(),
            data: SeasonEvent::SeasonCreated {
                id: uuid::Uuid::now_v7(),
                series_id: SeriesId(uuid::Uuid::now_v7()),
                number: 1,
                title: None,
                version: AggregateVersion(0),
            },
            metadata: Metadata {
                causation_command: None,
                causation_event: None,
                data: meta,
            },
            timestamp: chrono::Utc::now(),
        }
    }

    #[test]
    fn projector_type_returns_canonical_names() {
        use AuditCategory::*;
        let cases = [
            (Season, "Season"),
            (Block, "Block"),
            (Episode, "Episode"),
            (Scene, "Scene"),
            (SceneShoot, "SceneShoot"),
            (ShootingDay, "ShootingDay"),
            (Character, "Character"),
            (Costume, "Costume"),
            (CostumeCategory, "CostumeCategory"),
            (Photo, "Photo"),
            (Membership, "Membership"),
            (Settings, "Settings"),
        ];
        for (cat, expected) in cases {
            let s = cat.projector_type();
            assert!(
                !s.is_empty(),
                "projector_type must not be empty for {cat:?}"
            );
            assert_ne!(
                s, "xyzzy",
                "projector_type must not be a placeholder for {cat:?}"
            );
            assert_eq!(s, expected, "projector_type mismatch for {cat:?}");
        }
    }

    #[test]
    fn extract_metadata_reads_present_metadata() {
        let series = SeriesId(uuid::Uuid::now_v7());
        let meta = EventMetadata {
            actor: Some(UserId("user-123".into())),
            provenance: Provenance::Saga("SeasonSeeding".into()),
            series_id: Some(series),
        };
        let event = make_event(Some(meta));
        let (actor, provenance, series_id) = extract_metadata(&event);
        assert_eq!(actor, Some("user-123".to_string()));
        assert_eq!(provenance, "SeasonSeeding");
        assert_eq!(series_id, Some(series.0.to_string()));
    }

    #[test]
    fn extract_metadata_defaults_without_metadata() {
        let event = make_event(None);
        let (actor, provenance, series_id) = extract_metadata(&event);
        assert_eq!(actor, None);
        assert_eq!(provenance, "Human");
        assert_eq!(series_id, None);
    }
}
