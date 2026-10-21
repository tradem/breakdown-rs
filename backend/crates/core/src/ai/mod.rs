// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! AI-assisted script and shooting-schedule import bounded context.
//!
//! This module contains only domain types, deterministic preview logic, and
//! ports. Provider transports, persistence, subprocesses, and HTTP concerns
//! belong to `infra`/`api`.

pub mod aggregate;
pub mod bounds;
pub mod commands;
pub mod cost;
pub mod error;
pub mod events;
pub mod ports;
pub mod preview;
pub mod views;

pub use aggregate::AiConfig;
pub use bounds::AiImportBounds;
pub use commands::{CreateAiConfig, RevokeAiConfig, UpdateAiConfig};
pub use error::AiConfigError;
pub use events::AiConfigEvent;
pub use ports::LlmProvider;
pub use ports::{
    AiConfigCommands, AiConfigRepository, AiImportEnqueueRequest, AiImportEnqueueResult,
    AiImportMapping, AiImportMappingRepository, AiImportQueue, AiModelPricingRepository,
    CURATED_PROVIDERS, CuratedLlmProvider, LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient,
    LlmModelCatalog, ModelInfo, ModelPricingRow, PRIMARY_ORDINAL, mapping_kind,
};
pub use preview::{
    AiImportPreviewResponse, AiPreviewPayload, ApplyGateError, ApplyMapping, ApplyMappingDecision,
    CharacterApplyPlan, CostumeApplyPlan, CostumeBeatSlot, CostumeDecision, DraftCharacter,
    DraftCostume, DraftEpisode, DraftScene, DraftShootingDay, EpisodeGroupPlan, EpisodeTarget,
    MergeInput, MergedPreview, MergedScene, PlannedEpisode, PlannedShootingDay, RejectedCostume,
    RejectedCostumeReason, ReviewerDecisions, SceneApplyCommand, SceneApplyPlan, SceneBeatLane,
    SceneChunk, ScriptApplyPlan, ScriptContext, ShootingDayPlan, ShootingSchedule,
    ShootingScheduleRow, UnappliedCostume, UnappliedCostumeReason, Uncertainty,
    UncertaintyAcknowledgement, UncertaintyKind, category_conflict_uncertainties,
    character_identity, character_mapping_ref, draft_row_ref, ensure_merge_applyable,
    ensure_script_applyable, episode_group_refs, extract_scenes, is_meta_summary, merge_from_input,
    merge_schedule_to_scenes, parse_script_day, plan_scene_apply, sanitize_meta_summary,
    scene_beat_lanes, shooting_day_group_refs, stable_draft_ref, verify_draft_costumes,
};
pub use views::{
    AiConfigView, AiImportAttempt, AiImportJob, AiImportJobId, AiImportProgress, AiImportStage,
    CostBreakdown, CostDisplayPreference, CostStatus, Currency, DocumentKind, EnergyCostBreakdown,
    ImageCostBreakdown, JobStatus, JobTelemetrySummary, ModelPricing, PricingSource, SourceFormat,
    Telemetry, TelemetryApplyState, TokenCostBreakdown,
};
