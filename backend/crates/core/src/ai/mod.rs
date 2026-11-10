// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! AI-assisted script and shooting-schedule import bounded context.
//!
//! This module contains only domain types, deterministic preview logic, and
//! ports. Provider transports, persistence, subprocesses, and HTTP concerns
//! belong to `infra`/`api`.

pub mod aggregate;
pub mod bounds;
pub mod commands;
pub mod continuity;
pub mod cost;
pub mod decision;
pub mod error;
pub mod events;
pub mod ports;
pub mod preview;
pub mod provider_health;
pub mod source_name;
pub mod views;

pub use aggregate::AiConfig;
pub use bounds::AiImportBounds;
pub use commands::{CreateAiConfig, RevokeAiConfig, UpdateAiConfig};
pub use continuity::{
    CONTINUITY_MIN_CONFIDENCE, ContinuityOutcome, OutfitContinuityGap, PriorOutfit,
    PriorOutfitOwned, context_look_name, continuity_candidates, continuity_questions,
    continuity_state, has_plausible_action, outfit_continuity_gaps, prior_outfit,
    resolve_continuity_outcome,
};
pub use decision::{
    ChoiceOption, DecisionAnswer, DecisionCallOutcome, DecisionClient, DecisionQuestion,
    DecisionRequest, DecisionRubric, SCORE_MIN_LEVELS, SCORE5_LADDER, compute_scene_score,
    compute_shooting_day_score, compute_synopsis_score, curated_decision_model_ids,
    is_curated_decision_model, is_decision_capable, noul, question_keys, scene_grounding_factor,
    score, score5,
};
pub use error::AiConfigError;
pub use events::AiConfigEvent;
pub use ports::LlmProvider;
pub use ports::{
    AiConfigCommands, AiConfigRepository, AiImportEnqueueRequest, AiImportEnqueueResult,
    AiImportMapping, AiImportMappingRepository, AiImportQueue, AiModelPricingRepository,
    CURATED_PROVIDERS, CuratedLlmProvider, LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient,
    LlmModelCatalog, ModelInfo, ModelPricingRow, OpenBreaker, PRIMARY_ORDINAL, ProbeLease,
    ProbeOutcome, ProviderBreakerSnapshot, ProviderHealth, TargetAttachOutcome, UsageAccumulator,
    mapping_kind,
};
pub use preview::{
    AiImportPreviewResponse, AiPreviewPayload, ApplyGateError, ApplyMapping, ApplyMappingDecision,
    CategoryVocabularyEntry, CharacterApplyPlan, ContinuationPlan, DraftCharacter, DraftEpisode,
    DraftOutfit, DraftOutfitCandidate, DraftOutfitOrigin, DraftOutfitProvenance, DraftPiece,
    DraftScene, DraftShootingDay, EpisodeGroupPlan, EpisodeTarget, MergeInput, MergedPreview,
    MergedScene, OutfitApplyPlan, OutfitBeatSlot, OutfitContinuityCandidate,
    OutfitContinuitySelection, OutfitDecision, PieceApplyPlan, PlannedEpisode, PlannedShootingDay,
    RejectedOutfit, RejectedOutfitReason, ReviewerDecisions, SceneApplyCommand, SceneApplyPlan,
    SceneBeatLane, SceneChunk, ScriptApplyPlan, ScriptContext, ShootingDayPlan, ShootingSchedule,
    ShootingScheduleRow, UNCERTAINTY_FIELD_CHARACTERS, UnappliedOutfit, UnappliedOutfitReason,
    Uncertainty, UncertaintyAcknowledgement, UncertaintyKind, category_conflict_uncertainties,
    character_identity, character_mapping_ref, draft_row_ref, ensure_merge_applyable,
    ensure_script_applyable, episode_group_refs, extract_block_number, extract_scenes,
    is_meta_summary, merge_from_input, merge_schedule_to_scenes, parse_mood_from_heading,
    parse_schedule_scene_ref, parse_script_day, plan_scene_apply, sanitize_meta_summary,
    scene_beat_lanes, shooting_day_group_refs, stable_draft_ref, verify_draft_outfits,
};
pub use source_name::{MAX_SOURCE_FILE_NAME_CHARS, sanitize_source_file_name};
pub use views::{
    AiConfigView, AiImportAttempt, AiImportJob, AiImportJobId, AiImportProgress, AiImportStage,
    AiImportTarget, AiImportTargetRequest, AppliedEpisode, ApplyProgress, ApplyProgressFrame,
    ApplyRunId, ApplyRunState, ApplyStage, CostBreakdown, CostDisplayPreference, CostStatus,
    CostTotal, CostTotalStatus, Currency, DecisionCostBreakdown, DecisionOutcome,
    DecisionTelemetry, DocumentKind, EnergyCostBreakdown, ImageCostBreakdown, JobStatus,
    JobTelemetrySummary, ModelPricing, PricingSource, ProviderBreakerState, ProviderHold,
    SourceFormat, Telemetry, TelemetryApplyState, TokenCostBreakdown,
};
