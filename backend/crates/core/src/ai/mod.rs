// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! AI-assisted script and shooting-schedule import bounded context.
//!
//! This module contains only domain types, deterministic preview logic, and
//! ports. Provider transports, persistence, subprocesses, and HTTP concerns
//! belong to `infra`/`api`.

pub mod aggregate;
pub mod bounds;
pub mod commands;
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
    AiImportMapping, AiImportMappingRepository, AiImportQueue, CURATED_PROVIDERS,
    CuratedLlmProvider, LlmChatRequest, LlmClient, LlmModelCatalog, ModelInfo,
};
pub use preview::{
    ApplyGateError, ApplyMapping, ApplyMappingDecision, DraftScene, MergedPreview, MergedScene,
    SceneApplyCommand, SceneChunk, ScriptContext, ShootingSchedule, ShootingScheduleRow,
    Uncertainty, ensure_merge_applyable, ensure_script_applyable, extract_scenes,
    merge_schedule_to_scenes, plan_scene_apply,
};
pub use views::{
    AiConfigView, AiImportJob, AiImportJobId, DocumentKind, JobStatus, Telemetry,
    TelemetryApplyState,
};
