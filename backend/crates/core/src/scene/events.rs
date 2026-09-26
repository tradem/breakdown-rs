// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene events.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, ShootingDayId};

/// Provenance discriminator for how a `Scene` came into existence.
///
/// `Manual` is the user-created path (REST handler). `AiExtracted` marks a
/// scene created by the AI script import, carrying the import `document_id`
/// (the AI job id) and the `draft_ref` as `external_ref` — the data the EU AI
/// Act transparency provenance needs (issue #517).
///
/// `confidence` is `Option<f32>` from day one: the preview pipeline carries no
/// model confidence value, so the AI apply records `None` instead of inventing
/// one (in contrast to the legacy hard-coded `1.0` on `ShootingDaySource`).
///
/// Serialized as an externally-tagged enum, e.g. `{"Manual":null}` or
/// `{"AiExtracted":{"document_id":...,"external_ref":...,"confidence":null}}`,
/// which maps directly onto the `source JSONB` projection column.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default, utoipa::ToSchema)]
pub enum SceneSource {
    #[default]
    Manual,
    AiExtracted {
        document_id: Uuid,
        external_ref: Option<String>,
        confidence: Option<f32>,
    },
}

/// Serde default for `SceneCreated.source`: scenes created before this field
/// existed (and REST API clients that omit it) are user-created scenes, so
/// historic events replay as `Manual` without a data migration.
pub fn default_scene_source() -> SceneSource {
    SceneSource::Manual
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default, utoipa::ToSchema)]
pub struct SceneDetails {
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub is_schedule_set: bool,
    /// Free-form scene description/prose summary.
    pub summary: Option<String>,
    /// Fictional script-chronology day (e.g. "1. Spieltag"), distinct
    /// from the calendar `ShootingDay.date`. Free-form search index.
    pub script_day: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SceneEvent {
    SceneCreated {
        id: Uuid,
        episode_id: EpisodeId,
        details: SceneDetails,
        assigned_characters: Vec<Uuid>,
        /// Provenance: how this scene came into existence. Defaults to
        /// `Manual` so pre-#517 events (and wire payloads from older
        /// clients) keep replaying/deserializing unchanged.
        #[serde(default = "default_scene_source")]
        source: SceneSource,
        version: AggregateVersion,
    },
    SceneDetailsUpdated {
        id: Uuid,
        details: SceneDetails,
        version: AggregateVersion,
    },
    CharacterAssigned {
        id: Uuid,
        character_id: Uuid,
        version: AggregateVersion,
    },
    CharacterRemoved {
        id: Uuid,
        character_id: Uuid,
        version: AggregateVersion,
    },
    /// A `ShootingDay` was linked to this Scene (scene owns the collection).
    ShootingDayScheduled {
        id: Uuid,
        shooting_day_id: ShootingDayId,
        version: AggregateVersion,
    },
    /// A `ShootingDay` link was removed from this Scene.
    ShootingDayUnscheduled {
        id: Uuid,
        shooting_day_id: ShootingDayId,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for SceneEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::SceneCreated { .. } => "SceneCreated",
            Self::SceneDetailsUpdated { .. } => "SceneDetailsUpdated",
            Self::CharacterAssigned { .. } => "CharacterAssigned",
            Self::CharacterRemoved { .. } => "CharacterRemoved",
            Self::ShootingDayScheduled { .. } => "ShootingDayScheduled",
            Self::ShootingDayUnscheduled { .. } => "ShootingDayUnscheduled",
        }
    }
}
