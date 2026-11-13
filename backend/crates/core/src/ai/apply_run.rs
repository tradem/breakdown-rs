// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! The **persisted** apply request of an AI-import run (issue #899).
//!
//! # Why this type exists
//!
//! Until #899 the apply was executed by the HTTP handler that accepted it, so
//! the reviewer's decisions could stay borrowed references
//! (`infra::ai::ApplyScriptRequest<'a>`): the request outlived nothing. A
//! durable run reverses that — the `POST` returns `202`, and a **worker on any
//! replica** may execute the run later (after a rolling deploy, or as the
//! recovery path for a crashed dispatcher). The worker therefore needs the
//! resolved request as *owned, serializable* data on the job row (design D1/D2).
//!
//! # Why it is resolved at the API edge and not here
//!
//! Everything in [`ScriptApplyRunRequest`] is either reviewer input or a
//! read-model fact the API edge is the only legitimate consumer of (the target
//! episode's block/season, the episode labels, the season's category
//! vocabulary — CQRS boundary, `backend/AGENTS.md` §1). Persisting the
//! *resolved* request is what lets the write side stay free of projection
//! reads: the worker never has to re-derive what the reviewer already decided.
//!
//! # Lifecycle
//!
//! `POST /apply` → [`ApplyRunRequest`] serialized into `apply_request` JSONB
//! (`requested`) → [`ClaimedApplyRun`] read back by the worker (`running`) →
//! [`super::ApplyImportSummary`] persisted by `complete_apply_run`
//! ([`ApplyImportSummary`] in `apply_result`). The request itself is *not* part
//! of the job's wire view: it carries reviewer decisions and never leaves the
//! server.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::shared::{BlockId, EpisodeId, ProjectId, SeasonId, UserId};

use super::preview::{
    ApplyMapping, CategoryVocabularyEntry, EpisodeGroupPlan, OutfitContinuitySelection,
    ShootingDayPlan, UncertaintyAcknowledgement,
};
use super::views::{AiImportJobId, ApplyRunId, Telemetry};

/// Display identity of one episode an apply lands rows in (issue #763).
///
/// Resolved at the API edge (it is a read-model fact) and carried in the
/// persisted request so the worker can label its applied-episode summary
/// without querying a projection. A missing entry degrades the label to
/// `None` and never fails the apply — a display label must not be able to block
/// a write.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AppliedEpisodeIdentity {
    pub id: EpisodeId,
    pub number: i32,
    pub name: Option<String>,
}

/// Everything a script apply needs, resolved and owned (issue #899).
///
/// Field-for-field the owned twin of `infra::ai::ApplyScriptRequest`'s borrowed
/// parameters; the preview itself is deliberately **absent** — the worker loads
/// it from the preview store by the job's `preview_handle`, so a 60-scene
/// preview is stored once instead of being copied into the run row.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ScriptApplyRunRequest {
    /// The user whose apply this is (attribution on the emitted commands).
    pub actor: UserId,
    /// Primary target episode (the job's `X-Active-Block` episode).
    pub episode_id: EpisodeId,
    /// The target season — the wardrobe/character scope of the apply.
    pub season_id: SeasonId,
    /// The project seam resolved from the target episode at the API edge.
    pub project_id: Option<ProjectId>,
    /// Parent of episodes a draft group creates (issue #581).
    pub block_id: BlockId,
    /// The reviewer's mapping decisions, as received and validated.
    pub decisions: Vec<ApplyMapping>,
    /// Per-group episode targets keyed by the preview's group refs.
    pub episode_groups: Vec<EpisodeGroupPlan>,
    /// Display identities of the episodes rows can land in (issue #763).
    pub known_episodes: Vec<AppliedEpisodeIdentity>,
    /// Per-day decisions keyed by the preview's day-group refs (issue #706).
    pub shooting_days: Vec<ShootingDayPlan>,
    /// Reviewer acknowledgements of blocking uncertainties (issue #663).
    pub acknowledged_uncertainties: Vec<UncertaintyAcknowledgement>,
    /// The target season's category vocabulary, loaded at the API edge.
    pub categories: Vec<CategoryVocabularyEntry>,
    /// Per-gap continuity resolutions (OpenSpec
    /// `ai-import-decision-outfit-continuity`).
    pub continuity_selections: Vec<OutfitContinuitySelection>,
    /// Telemetry to record once the run ends. `None` when the edge decided not
    /// to record any (it is never required for the apply to succeed).
    #[serde(default)]
    pub telemetry: Option<Telemetry>,
}

/// Everything a schedule apply needs, resolved and owned (issue #899).
// No `PartialEq`/`Eq`: the telemetry the request now carries is float-valued
// (`Telemetry`), and comparing two persisted requests is nothing the run does.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ScheduleApplyRunRequest {
    pub actor: UserId,
    /// The project the schedule merges into.
    pub project_id: Option<ProjectId>,
    /// Telemetry to record once the run ends — the same contract the script
    /// branch carries. It exists because #899 moved the run out of the handler:
    /// the handler used to record it after a successful schedule merge, and a
    /// dispatched run has no handler left to do that. `None` when the edge
    /// decided not to record any (it is never required for the apply to
    /// succeed).
    #[serde(default)]
    pub telemetry: Option<Telemetry>,
}

/// The persisted request of one apply run (issue #899, design D2).
///
/// Tagged by `kind` so one `apply_request` column carries both document kinds —
/// the job row already says which kind it is, but the tag makes the payload
/// self-describing: a queue that decodes a JSONB blob into the wrong variant
/// would otherwise fail at the first field instead of at the discriminator.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ApplyRunRequest {
    /// A script apply's reviewer request. Boxed for the same reason as
    /// [`ApplyRunOutcome::Succeeded`]: the script payload is ~15× the schedule
    /// one (decisions, groups, day plans, category vocabulary), and the enum
    /// travels by value through the queue and the runner
    /// (`clippy::large_enum_variant`).
    Script(Box<ScriptApplyRunRequest>),
    /// Boxed for the same reason as [`Self::Script`]: with the run's telemetry
    /// it carries ~544 bytes against the boxed script variant's pointer, and the
    /// request travels by value through the queue into the runner
    /// (`clippy::large_enum_variant`).
    Schedule(Box<ScheduleApplyRunRequest>),
}

/// A run a worker has just taken ownership of (issue #899).
///
/// Returned by `AiImportQueue::begin_apply_run`, which is the single atomic
/// transition `requested` → `running` (or `running` + stale → `running` under a
/// new run id). `run_id` is the identity the worker must use for every
/// subsequent fenced write — for a fresh dispatch it is the id the client
/// already received in its `202`, for a takeover it is a new one (both runs must
/// never share an identity: the dead owner's late write has to fail the fence).
#[derive(Debug, Clone)]
pub struct ClaimedApplyRun {
    /// The job whose slot this worker now owns.
    pub job_id: AiImportJobId,
    /// The run identity every fenced write of this execution must carry.
    pub run_id: ApplyRunId,
    /// The persisted reviewer request to execute.
    pub request: ApplyRunRequest,
}
