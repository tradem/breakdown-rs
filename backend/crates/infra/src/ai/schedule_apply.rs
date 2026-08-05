// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use breakdown_core::ai::{
    AiImportJobId, AiImportMapping, AiImportMappingRepository, MergedPreview,
    ensure_merge_applyable,
};
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::ScheduleSceneOnShootingDay;
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::scene_shoot::commands::PlanSceneShoot;
use breakdown_core::scene_shoot::ports::SceneShootCommands;
use breakdown_core::shared::{
    AggregateVersion, EpisodeId, LexicalSortKey, SeriesId, ShootingDayId, UserId,
};
use breakdown_core::shooting_day::commands::CreateShootingDay;
use breakdown_core::shooting_day::events::ShootingDaySource;
use breakdown_core::shooting_day::ports::ShootingDayCommands;
use uuid::Uuid;

/// Reviewed schedule-side apply request. `series_id` is supplied by the API
/// edge and is never looked up by this write-side worker.
pub struct ScheduleApplyRequest<'a> {
    pub actor: UserId,
    pub preview_id: AiImportJobId,
    pub preview: &'a MergedPreview,
    pub series_id: Option<SeriesId>,
}

pub struct ScheduleApplyWorker<SC, SD, SS, M> {
    pub scene_commands: Arc<SC>,
    pub shooting_day_commands: Arc<SD>,
    pub scene_shoot_commands: Arc<SS>,
    pub mappings: Arc<M>,
}

impl<SC, SD, SS, M> ScheduleApplyWorker<SC, SD, SS, M>
where
    SC: SceneCommands + 'static,
    SD: ShootingDayCommands + 'static,
    SS: SceneShootCommands + 'static,
    M: AiImportMappingRepository + 'static,
{
    pub async fn apply(
        &self,
        request: ScheduleApplyRequest<'_>,
    ) -> Result<ScheduleApplyResult, DomainError> {
        ensure_merge_applyable(request.preview)
            .map_err(|error| DomainError::Conflict(error.to_string()))?;

        let mut day_by_key: HashMap<String, AppliedDay> = HashMap::new();
        let mut scene_versions: HashMap<Uuid, AggregateVersion> = request
            .preview
            .scenes
            .iter()
            .map(|merged| (merged.scene.id, merged.scene.version))
            .collect();
        let mut created_days = 0u32;
        let mut planned_scene_shoots = 0u32;

        // Fallback order keys must live above every supplied order, otherwise a
        // missing `row.order` can collide with (or reorder before) an explicit
        // one.
        let max_supplied_order = request
            .preview
            .scenes
            .iter()
            .flat_map(|merged| merged.schedule_rows.iter())
            .filter_map(|row| row.order)
            .max()
            .unwrap_or(0);
        // Monotonic counter for fallback orders: `scene_index + row_index` is
        // not unique across the nested loops (scene 0 row 1 == scene 1 row 0).
        let mut fallback_order: u32 = max_supplied_order;

        for merged in request.preview.scenes.iter() {
            for row in merged.schedule_rows.iter() {
                let day_key = format!(
                    "shooting-day:{}:{}:{}",
                    merged.scene.episode_id.0,
                    row.date.map(|date| date.to_string()).unwrap_or_default(),
                    row.shooting_day_label.as_deref().unwrap_or_default()
                );
                let day = if let Some(day) = day_by_key.get(&day_key) {
                    *day
                } else {
                    let day = self
                        .resolve_day(
                            request.actor.clone(),
                            DayDraft {
                                preview_id: request.preview_id,
                                draft_ref: day_key.clone(),
                                episode_id: merged.scene.episode_id,
                                label: row.shooting_day_label.clone(),
                                date: row.date,
                                series_id: request.series_id,
                            },
                        )
                        .await?;
                    if day.created {
                        created_days += 1;
                    }
                    day_by_key.insert(day_key.clone(), day);
                    day
                };

                let pair_key = format!("scene-shoot:{}:{}", merged.scene.id, day.id.0);
                // Read the idempotency projection (non-audit): the spec requires
                // the mapping lookup so a retried apply dispatches Update…
                // instead of duplicating a scene shoot. Not audit-context
                // resolution — series_id comes from the API edge request.
                // (Suppression directive on the find line below.)
                if self
                    .mappings
                    .find(request.preview_id, &pair_key) // ast-grep-ignore: cqrs-boundary
                    .await?
                    .is_some()
                {
                    continue;
                }

                let scene_version =
                    scene_versions
                        .get(&merged.scene.id)
                        .copied()
                        .ok_or_else(|| {
                            DomainError::ValidationError(format!(
                                "missing scene version for {}",
                                merged.scene.id
                            ))
                        })?;
                let scene_version = self
                    .scene_commands
                    .schedule_on_shooting_day(
                        request.actor.clone(),
                        ScheduleSceneOnShootingDay {
                            id: merged.scene.id,
                            shooting_day_id: day.id,
                            series_id: request.series_id,
                            version: scene_version,
                        },
                    )
                    .await?;
                scene_versions.insert(merged.scene.id, scene_version);

                let order = row.order.unwrap_or_else(|| {
                    // Offset above every supplied order and unique per fallback.
                    fallback_order = fallback_order.saturating_add(1);
                    fallback_order
                });
                let planned_order = LexicalSortKey::new(format!("{order:08}"))
                    .map_err(|error| DomainError::ValidationError(error.to_string()))?;
                let (scene_shoot_id, version) = self
                    .scene_shoot_commands
                    .plan(
                        request.actor.clone(),
                        PlanSceneShoot {
                            id: breakdown_core::shared::SceneShootId::new(),
                            scene_id: merged.scene.id,
                            shooting_day_id: day.id,
                            series_id: request.series_id,
                            planned_order,
                        },
                    )
                    .await?;
                self.mappings
                    .insert(AiImportMapping {
                        preview_id: request.preview_id,
                        draft_ref: pair_key,
                        aggregate_kind: "scene_shoot".to_owned(),
                        aggregate_id: scene_shoot_id.0,
                        aggregate_version: version,
                    })
                    .await?;
                planned_scene_shoots += 1;
            }
        }

        Ok(ScheduleApplyResult {
            created_days,
            planned_scene_shoots,
        })
    }

    async fn resolve_day(&self, actor: UserId, draft: DayDraft) -> Result<AppliedDay, DomainError> {
        // Read the idempotency projection (non-audit): a retried apply must
        // reuse the previously created shooting day instead of creating a
        // duplicate. series_id comes from the API edge request, not this read.
        // (Suppression directive on the find line below.)
        if let Some(mapping) = self
            .mappings
            .find(draft.preview_id, &draft.draft_ref) // ast-grep-ignore: cqrs-boundary
            .await?
        {
            return Ok(AppliedDay {
                id: ShootingDayId::from_uuid(mapping.aggregate_id),
                version: mapping.aggregate_version,
                created: false,
            });
        }
        let order_key = LexicalSortKey::new(format!("day-{}", Uuid::now_v7()))
            .map_err(|error| DomainError::ValidationError(error.to_string()))?;
        let id = ShootingDayId::new();
        let (id, version) = self
            .shooting_day_commands
            .create(
                actor,
                CreateShootingDay {
                    id,
                    episode_id: draft.episode_id,
                    series_id: draft.series_id,
                    label: draft.label,
                    order_key,
                    date: draft.date,
                    source: ShootingDaySource::AiExtracted {
                        document_id: draft.preview_id.as_uuid(),
                        external_ref: Some(draft.draft_ref.clone()),
                        confidence: 1.0,
                    },
                },
            )
            .await?;
        self.mappings
            .insert(AiImportMapping {
                preview_id: draft.preview_id,
                draft_ref: draft.draft_ref,
                aggregate_kind: "shooting_day".to_owned(),
                aggregate_id: id.0,
                aggregate_version: version,
            })
            .await?;
        Ok(AppliedDay {
            id,
            version,
            created: true,
        })
    }
}

struct DayDraft {
    preview_id: AiImportJobId,
    draft_ref: String,
    episode_id: EpisodeId,
    label: Option<String>,
    date: Option<chrono::NaiveDate>,
    series_id: Option<SeriesId>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AppliedDay {
    pub id: ShootingDayId,
    pub version: AggregateVersion,
    pub created: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ScheduleApplyResult {
    pub created_days: u32,
    pub planned_scene_shoots: u32,
}
