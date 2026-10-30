// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use thiserror::Error;
use uuid::Uuid;

use crate::ai::error::AiConfigError;
use crate::block::error::BlockError;
use crate::character::error::CharacterError;
use crate::costume_category::error::CostumeCategoryError;
use crate::episode::error::EpisodeError;
use crate::error_registry::{
    AI_CONFIG_ALREADY_REVOKED, AI_CONFIG_DECISION_INCOMPLETE, AI_CONFIG_DECISION_MODEL_EMPTY,
    AI_CONFIG_DECISION_MODEL_UNKNOWN, AI_CONFIG_DECISION_PROVIDER_UNSUPPORTED,
    AI_CONFIG_DECISION_VAULT_KEY_EMPTY, AI_CONFIG_EMPTY_MODEL, AI_CONFIG_EMPTY_PROMPT,
    AI_CONFIG_EMPTY_PROVIDER, AI_CONFIG_EMPTY_VAULT_KEY, AI_CONFIG_NOT_FOUND,
    AI_CONFIG_PROVIDER_MISMATCH, BLOCK_NOT_FOUND, CHARACTER_NOT_FOUND, CHARACTER_VALIDATION,
    CONCURRENCY_VERSION_MISMATCH, COSTUME_CATEGORY_ARCHIVED, COSTUME_CATEGORY_SEASON_MISMATCH,
    COSTUME_CATEGORY_VALIDATION, DEPENDENCY_AUTH_FAILED, DOMAIN_CONFLICT, DOMAIN_FORBIDDEN,
    DOMAIN_NOT_FOUND, DOMAIN_SERVICE_UNAVAILABLE, DOMAIN_VALIDATION, EPISODE_NOT_FOUND,
    HTTP_INTERNAL_ERROR, MEMBERSHIP_ALREADY_INVITED, MEMBERSHIP_BOOTSTRAP_NOT_ALLOWED,
    MEMBERSHIP_MISSING_ACTOR, MEMBERSHIP_NO_PENDING_INVITATION, MEMBERSHIP_NOT_ACTIVE_MEMBER,
    MEMBERSHIP_NOT_FOUND, OUTFIT_NOT_FOUND, OUTFIT_VALIDATION, PHOTO_ALREADY_DELETED,
    PHOTO_NOT_FOUND, PHOTO_VALIDATION, PIECE_DETAIL_NOT_FOUND, PIECE_NOT_FOUND, PIECE_VALIDATION,
    ProblemCode, SCENE_ALREADY_SCHEDULED, SCENE_BEAT_NOT_FOUND, SCENE_CHARACTER_ALREADY_ASSIGNED,
    SCENE_CHARACTER_NOT_FOUND, SCENE_CHARACTER_NOT_IN_SCENE, SCENE_NOT_FOUND, SCENE_NOT_SCHEDULED,
    SCENE_SHOOT_ALREADY_LINKED, SCENE_SHOOT_ALREADY_STARTED, SCENE_SHOOT_NOT_FOUND,
    SCENE_SHOOT_NOTE_NOT_FOUND, SCENE_SHOOT_PAIR_ALREADY_EXISTS, SCENE_SHOOT_PLANNED_ORDER_FROZEN,
    SCENE_SHOOT_SHOOTING_DAY_WRAPPED, SCENE_SHOOT_TERMINAL_STATE, SCENE_SHOOT_VALIDATION,
    SCENE_VALIDATION, SEASON_NOT_FOUND, SETTINGS_ALREADY_REVOKED, SETTINGS_EMPTY_PROVIDER,
    SETTINGS_EMPTY_VAULT_KEY, SETTINGS_NOT_FOUND, SETTINGS_PROVIDER_MISMATCH,
    SHOOTING_DAY_ARCHIVED, SHOOTING_DAY_DUPLICATE_ORDER_KEY, SHOOTING_DAY_NOT_FOUND,
    SHOOTING_DAY_TARGET_WRAPPED, SHOOTING_DAY_VALIDATION,
};
use crate::membership::error::MembershipError;
use crate::outfit::error::OutfitError;
use crate::photo::error::PhotoError;
use crate::piece::error::PieceError;
use crate::scene::error::SceneError;
use crate::scene_shoot::error::SceneShootError;
use crate::season::error::SeasonError;
use crate::settings::error::SettingsError;
use crate::shared::AggregateVersion;
use crate::shooting_day::error::ShootingDayError;

/// The API-facing domain error (ADR-031 D3).
///
/// Structured — never string-carrying at the boundary. Every variant carries
/// its registry entry (`code`, ADR-031 D2) and typed data; the HTTP layer
/// renders `application/problem+json` from the registry, and only declared
/// S0/S1 fields may appear as extensions (S2 person identifiers are
/// structurally excluded — membership errors drop the `user_id`).
///
/// `Display`/`to_string()` is for server logs and tests only; the wire
/// `detail` is the registry title / localized text, never this string
/// (http-error-surface spec).
#[derive(Error, Debug, Clone, PartialEq)]
pub enum DomainError {
    /// Resource not found (or deliberately hidden per the existence-oracle
    /// policy, ADR-031 decision 5). `resource` is a stable slug ("scene",
    /// "costume", …) used in logs; `code` is the per-context registry entry.
    #[error("not found: {resource} {id}")]
    NotFound {
        code: &'static ProblemCode,
        resource: &'static str,
        id: Uuid,
    },

    /// Authenticated caller lacks permission (403).
    #[error("forbidden: {reason}")]
    Forbidden {
        code: &'static ProblemCode,
        reason: String,
    },

    /// Well-formed request that violates a domain rule (422).
    #[error("validation failed: {reason}")]
    Validation {
        code: &'static ProblemCode,
        reason: String,
    },

    /// State conflict (409).
    #[error("conflict: {reason}")]
    Conflict {
        code: &'static ProblemCode,
        reason: String,
    },

    /// Upstream dependency unavailable (503).
    #[error("service unavailable: {reason}")]
    ServiceUnavailable {
        code: &'static ProblemCode,
        reason: String,
    },

    /// Upstream dependency rejected our credential (401/403, invalid or
    /// expired token). Distinct from [`DomainError::ServiceUnavailable`] so
    /// callers can tell a permanent misconfiguration from a transient outage
    /// and fail fast instead of retrying (issue #637). HTTP 503 with the
    /// `dependency.auth-failed` code.
    #[error("dependency authentication failed: {reason}")]
    DependencyAuthFailed {
        code: &'static ProblemCode,
        reason: String,
    },

    /// Server-side fault (500, `http.internal-error`) — persisted projection
    /// drift, internal failures. `reason` is log-only; internal text never
    /// reaches the wire (http-error-surface spec). The code is fixed to
    /// `http.internal-error` by construction — the variant cannot carry a
    /// different registry entry.
    #[error("internal error: {reason}")]
    Internal { reason: String },

    /// Optimistic-concurrency failure (409, `concurrency.version-mismatch`).
    #[error("version conflict: expected {expected:?}, current {current:?}")]
    VersionConflict {
        expected: AggregateVersion,
        current: AggregateVersion,
    },

    /// Scene already scheduled on another day (409, `scene.already-scheduled`).
    /// `shooting_day_id` is S1 — rendered only after the handler's authz gate.
    #[error("scene is already scheduled on shooting day {shooting_day_id}")]
    AlreadyScheduled { shooting_day_id: Uuid },

    /// Scene not scheduled on the given day (409, `scene.not-scheduled`).
    /// `shooting_day_id` is S0 (client-supplied in the request).
    #[error("scene is not scheduled on shooting day {shooting_day_id}")]
    NotScheduled { shooting_day_id: Uuid },

    /// Continuity photo already linked to this scene shoot (409,
    /// `scene-shoot.already-linked`). `photo_id` is S1.
    #[error("continuity photo {photo_id} is already linked to this scene shoot")]
    AlreadyLinked { photo_id: Uuid },

    /// Execution transition on a wrapped shooting day (409,
    /// `scene-shoot.shooting-day-wrapped`). Planning (Soll) stays allowed
    /// post-wrap; only execution transitions are frozen (issue #376).
    /// `shooting_day_id` is S0 (client-supplied in the request path).
    #[error("shooting day {shooting_day_id} is wrapped; execution is frozen")]
    ShootingDayWrapped { shooting_day_id: Uuid },

    /// The shooting-day link endpoint refused a **wrapped target day** (409,
    /// `shooting-day.target-wrapped`, issue #706 wrap finality: a script-
    /// derived planned day is never merged onto a finalised day). Distinct
    /// from [`DomainError::ShootingDayWrapped`] (the scene-shoot execution
    /// freeze, code `scene-shoot.shooting-day-wrapped`) so the schedule
    /// screen can point at the link action instead of an execution
    /// transition. `shooting_day_id` is S0 (client-supplied in the request
    /// path).
    #[error(
        "target shooting day {shooting_day_id} is wrapped; a planned day cannot be merged onto it"
    )]
    ShootingDayTargetWrapped { shooting_day_id: Uuid },

    /// Costume category from a foreign season (409,
    /// `costume-category.season-mismatch`, issue #543). A piece's permitted
    /// season set is exactly its repertoire; the API edge pre-checks it before
    /// dispatch. `category_id` is S0 (client-supplied in the request body).
    #[error("costume category {category_id} belongs to a season outside the piece's repertoire")]
    CategorySeasonMismatch { category_id: Uuid },
}

impl From<AiConfigError> for DomainError {
    fn from(error: AiConfigError) -> Self {
        match error {
            AiConfigError::NotFound => DomainError::NotFound {
                code: &AI_CONFIG_NOT_FOUND,
                resource: "ai-config",
                id: Uuid::nil(),
            },
            AiConfigError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
            AiConfigError::ProviderMismatch => DomainError::Conflict {
                code: &AI_CONFIG_PROVIDER_MISMATCH,
                reason: "provider cannot change".into(),
            },
            AiConfigError::AlreadyRevoked => DomainError::Conflict {
                code: &AI_CONFIG_ALREADY_REVOKED,
                reason: "already revoked".into(),
            },
            AiConfigError::EmptyProvider => DomainError::Validation {
                code: &AI_CONFIG_EMPTY_PROVIDER,
                reason: "provider must not be empty".into(),
            },
            AiConfigError::EmptyModel => DomainError::Validation {
                code: &AI_CONFIG_EMPTY_MODEL,
                reason: "assistant model must not be empty".into(),
            },
            AiConfigError::EmptyPrompt => DomainError::Validation {
                code: &AI_CONFIG_EMPTY_PROMPT,
                reason: "prompt must not be empty".into(),
            },
            AiConfigError::EmptyVaultKey => DomainError::Validation {
                code: &AI_CONFIG_EMPTY_VAULT_KEY,
                reason: "vault key reference must not be empty".into(),
            },
            AiConfigError::DecisionProviderUnsupported => DomainError::Validation {
                code: &AI_CONFIG_DECISION_PROVIDER_UNSUPPORTED,
                reason: "provider does not host decision models".into(),
            },
            AiConfigError::DecisionProviderRequired => DomainError::Validation {
                code: &AI_CONFIG_DECISION_INCOMPLETE,
                reason: "decision model configuration is incomplete".into(),
            },
            AiConfigError::EmptyDecisionModel => DomainError::Validation {
                code: &AI_CONFIG_DECISION_MODEL_EMPTY,
                reason: "decision model must not be empty".into(),
            },
            AiConfigError::DecisionModelUnknown => DomainError::Validation {
                code: &AI_CONFIG_DECISION_MODEL_UNKNOWN,
                reason: "decision model is not curated for the provider".into(),
            },
            AiConfigError::EmptyDecisionVaultKey => DomainError::Validation {
                code: &AI_CONFIG_DECISION_VAULT_KEY_EMPTY,
                reason: "decision vault key reference must not be empty".into(),
            },
        }
    }
}

impl From<SceneError> for DomainError {
    fn from(err: SceneError) -> Self {
        match err {
            SceneError::ValidationError(msg) => DomainError::Validation {
                code: &SCENE_VALIDATION,
                reason: msg,
            },
            SceneError::CharacterNotFound { id } => DomainError::NotFound {
                code: &SCENE_CHARACTER_NOT_FOUND,
                resource: "scene-character",
                id,
            },
            SceneError::NotFound { id } => DomainError::NotFound {
                code: &SCENE_NOT_FOUND,
                resource: "scene",
                id,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            SceneError::Deleted { id } => DomainError::NotFound {
                code: &SCENE_NOT_FOUND,
                resource: "scene",
                id,
            },
            SceneError::CharacterAlreadyAssigned => DomainError::Conflict {
                code: &SCENE_CHARACTER_ALREADY_ASSIGNED,
                reason: "character already assigned to this scene".into(),
            },
            SceneError::CharacterNotInScene { character_id } => DomainError::Validation {
                code: &SCENE_CHARACTER_NOT_IN_SCENE,
                reason: format!("character {character_id} is not assigned to this scene"),
            },
            SceneError::BeatNotFound {
                character_id,
                order,
            } => DomainError::Validation {
                code: &SCENE_BEAT_NOT_FOUND,
                reason: format!("no outfit beat for character {character_id} at order {order}"),
            },
            SceneError::NoOutfitBeats { character_id } => DomainError::Validation {
                code: &SCENE_BEAT_NOT_FOUND,
                reason: format!("no outfit beats for character {character_id}"),
            },
            SceneError::AlreadyScheduled { shooting_day_id } => DomainError::AlreadyScheduled {
                shooting_day_id: shooting_day_id.0,
            },
            SceneError::NotScheduled { shooting_day_id } => DomainError::NotScheduled {
                shooting_day_id: shooting_day_id.0,
            },
            SceneError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<CharacterError> for DomainError {
    fn from(err: CharacterError) -> Self {
        match err {
            CharacterError::ValidationError(msg) => DomainError::Validation {
                code: &CHARACTER_VALIDATION,
                reason: msg,
            },
            CharacterError::NotFound { id } => DomainError::NotFound {
                code: &CHARACTER_NOT_FOUND,
                resource: "character",
                id,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            CharacterError::Deleted { id } => DomainError::NotFound {
                code: &CHARACTER_NOT_FOUND,
                resource: "character",
                id,
            },
            CharacterError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<PieceError> for DomainError {
    fn from(err: PieceError) -> Self {
        match err {
            PieceError::EmptyName => DomainError::Validation {
                code: &PIECE_VALIDATION,
                reason: "piece name must not be empty".into(),
            },
            PieceError::ValidationError(msg) => DomainError::Validation {
                code: &PIECE_VALIDATION,
                reason: msg,
            },
            PieceError::NotFound { id } => DomainError::NotFound {
                code: &PIECE_NOT_FOUND,
                resource: "piece",
                id,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            PieceError::Deleted { id } => DomainError::NotFound {
                code: &PIECE_NOT_FOUND,
                resource: "piece",
                id,
            },
            // Issue #544: the piece exists, the addressed detail does not.
            // A distinct 404 code (not `piece.validation` 422) so the client
            // can tell the two apart and reconcile by refetching.
            PieceError::DetailNotFound { id } => DomainError::NotFound {
                code: &PIECE_DETAIL_NOT_FOUND,
                resource: "piece-detail",
                id,
            },
            PieceError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<OutfitError> for DomainError {
    fn from(err: OutfitError) -> Self {
        match err {
            OutfitError::EmptyName => DomainError::Validation {
                code: &OUTFIT_VALIDATION,
                reason: "outfit name must not be empty".into(),
            },
            OutfitError::ValidationError(msg) => DomainError::Validation {
                code: &OUTFIT_VALIDATION,
                reason: msg,
            },
            OutfitError::NotFound { id } => DomainError::NotFound {
                code: &OUTFIT_NOT_FOUND,
                resource: "outfit",
                id,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            OutfitError::Deleted { id } => DomainError::NotFound {
                code: &OUTFIT_NOT_FOUND,
                resource: "outfit",
                id,
            },
            OutfitError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<ShootingDayError> for DomainError {
    fn from(err: ShootingDayError) -> Self {
        match err {
            ShootingDayError::ValidationError(msg) => DomainError::Validation {
                code: &SHOOTING_DAY_VALIDATION,
                reason: msg,
            },
            ShootingDayError::NotFound { id } => DomainError::NotFound {
                code: &SHOOTING_DAY_NOT_FOUND,
                resource: "shooting-day",
                id: id.0,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            ShootingDayError::Deleted { id } => DomainError::NotFound {
                code: &SHOOTING_DAY_NOT_FOUND,
                resource: "shooting-day",
                id: id.0,
            },
            ShootingDayError::ArchivedCannotBeMutated { .. } => DomainError::Conflict {
                code: &SHOOTING_DAY_ARCHIVED,
                reason: "shooting day is archived and cannot be mutated".into(),
            },
            ShootingDayError::DuplicateOrderKey(key) => DomainError::Conflict {
                code: &SHOOTING_DAY_DUPLICATE_ORDER_KEY,
                reason: format!("order key {key} already exists for this episode"),
            },
            ShootingDayError::Wrapped { id } => DomainError::ShootingDayWrapped {
                shooting_day_id: id.0,
            },
            ShootingDayError::VersionMismatch { expected, actual } => {
                DomainError::VersionConflict {
                    expected,
                    current: actual,
                }
            }
        }
    }
}

impl From<SeasonError> for DomainError {
    fn from(err: SeasonError) -> Self {
        match err {
            SeasonError::ValidationError(msg) => DomainError::Validation {
                code: &crate::error_registry::SEASON_VALIDATION,
                reason: msg,
            },
            SeasonError::NotFound { id } => DomainError::NotFound {
                code: &SEASON_NOT_FOUND,
                resource: "season",
                id,
            },
            SeasonError::ArchivedCannotBeMutated { id } => DomainError::Conflict {
                code: &crate::error_registry::SEASON_ARCHIVED,
                reason: format!("season {id} is archived and cannot be mutated"),
            },
            SeasonError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<BlockError> for DomainError {
    fn from(err: BlockError) -> Self {
        match err {
            BlockError::ValidationError(msg) => DomainError::Validation {
                code: &crate::error_registry::BLOCK_VALIDATION,
                reason: msg,
            },
            BlockError::NotFound { id } => DomainError::NotFound {
                code: &BLOCK_NOT_FOUND,
                resource: "block",
                id,
            },
            BlockError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<CostumeCategoryError> for DomainError {
    fn from(err: CostumeCategoryError) -> Self {
        match err {
            CostumeCategoryError::ValidationError(msg) => DomainError::Validation {
                code: &COSTUME_CATEGORY_VALIDATION,
                reason: msg,
            },
            CostumeCategoryError::ArchivedCannotBeMutated { .. } => DomainError::Conflict {
                code: &COSTUME_CATEGORY_ARCHIVED,
                reason: "costume category is archived and cannot be mutated".into(),
            },
            CostumeCategoryError::VersionMismatch { expected, actual } => {
                DomainError::VersionConflict {
                    expected,
                    current: actual,
                }
            }
        }
    }
}

impl From<EpisodeError> for DomainError {
    fn from(err: EpisodeError) -> Self {
        match err {
            EpisodeError::ValidationError(msg) => DomainError::Validation {
                code: &crate::error_registry::EPISODE_VALIDATION,
                reason: msg,
            },
            EpisodeError::NotFound { id } => DomainError::NotFound {
                code: &EPISODE_NOT_FOUND,
                resource: "episode",
                id,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            EpisodeError::Deleted { id } => DomainError::NotFound {
                code: &EPISODE_NOT_FOUND,
                resource: "episode",
                id,
            },
            EpisodeError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<MembershipError> for DomainError {
    fn from(err: MembershipError) -> Self {
        match err {
            MembershipError::ValidationError(msg) => DomainError::Validation {
                code: &crate::error_registry::MEMBERSHIP_VALIDATION,
                reason: msg,
            },
            MembershipError::AlreadyInvited { user_id: _ } => DomainError::Conflict {
                // S2 ban (ADR-031 D4): the invited identity (OIDC `sub`) is
                // deliberately not carried — "already invited", never who.
                code: &MEMBERSHIP_ALREADY_INVITED,
                reason: "user already has a pending invitation".into(),
            },
            MembershipError::NoPendingInvitation { user_id: _ } => DomainError::Conflict {
                code: &MEMBERSHIP_NO_PENDING_INVITATION,
                reason: "no pending invitation".into(),
            },
            MembershipError::NotActiveMember { user_id: _ } => DomainError::Conflict {
                code: &MEMBERSHIP_NOT_ACTIVE_MEMBER,
                reason: "user is not an active member".into(),
            },
            MembershipError::MissingActor => DomainError::Validation {
                code: &MEMBERSHIP_MISSING_ACTOR,
                reason: "leave requires an authenticated actor".into(),
            },
            MembershipError::BootstrapNotAllowed { .. } => DomainError::Conflict {
                code: &MEMBERSHIP_BOOTSTRAP_NOT_ALLOWED,
                reason: "bootstrap is only allowed on an empty block".into(),
            },
            MembershipError::NotFound { id } => DomainError::NotFound {
                code: &MEMBERSHIP_NOT_FOUND,
                resource: "membership",
                id: id.0,
            },
        }
    }
}

impl From<SceneShootError> for DomainError {
    fn from(err: SceneShootError) -> Self {
        match err {
            SceneShootError::ValidationError(msg) => DomainError::Validation {
                code: &SCENE_SHOOT_VALIDATION,
                reason: msg,
            },
            SceneShootError::NotFound { id } => DomainError::NotFound {
                code: &SCENE_SHOOT_NOT_FOUND,
                resource: "scene-shoot",
                id: id.0,
            },
            // A deleted aggregate is gone for every consumer (issue #770).
            SceneShootError::Deleted { id } => DomainError::NotFound {
                code: &SCENE_SHOOT_NOT_FOUND,
                resource: "scene-shoot",
                id: id.0,
            },
            SceneShootError::PairAlreadyExists => DomainError::Conflict {
                code: &SCENE_SHOOT_PAIR_ALREADY_EXISTS,
                reason: "a scene shoot already exists for this (scene, shooting_day) pair".into(),
            },
            SceneShootError::VersionMismatch {
                expected, actual, ..
            } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
            SceneShootError::PlannedOrderFrozen => DomainError::Conflict {
                code: &SCENE_SHOOT_PLANNED_ORDER_FROZEN,
                reason: "planned order is frozen".into(),
            },
            SceneShootError::NoteNotFound { note_id } => DomainError::NotFound {
                code: &SCENE_SHOOT_NOTE_NOT_FOUND,
                resource: "scene-shoot-note",
                id: note_id,
            },
            SceneShootError::AlreadyLinked { photo_id } => DomainError::AlreadyLinked {
                photo_id: photo_id.0,
            },
            SceneShootError::AlreadyStarted => DomainError::Conflict {
                code: &SCENE_SHOOT_ALREADY_STARTED,
                reason: "scene shoot is already started".into(),
            },
            SceneShootError::TerminalState { status } => DomainError::Conflict {
                code: &SCENE_SHOOT_TERMINAL_STATE,
                reason: format!("scene shoot is in terminal state {status:?}"),
            },
        }
    }
}

impl From<SettingsError> for DomainError {
    fn from(err: SettingsError) -> Self {
        match err {
            SettingsError::EmptyProvider => DomainError::Validation {
                code: &SETTINGS_EMPTY_PROVIDER,
                reason: "credential provider must not be empty".into(),
            },
            SettingsError::EmptyVaultKey => DomainError::Validation {
                code: &SETTINGS_EMPTY_VAULT_KEY,
                reason: "vault key reference must not be empty".into(),
            },
            SettingsError::ProviderMismatch => DomainError::Conflict {
                code: &SETTINGS_PROVIDER_MISMATCH,
                reason: "credential provider cannot change during rotation".into(),
            },
            SettingsError::NotFound => DomainError::NotFound {
                code: &SETTINGS_NOT_FOUND,
                resource: "settings-credential",
                id: Uuid::nil(),
            },
            SettingsError::AlreadyRevoked => DomainError::Conflict {
                code: &SETTINGS_ALREADY_REVOKED,
                reason: "credential binding is already revoked".into(),
            },
            SettingsError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

impl From<PhotoError> for DomainError {
    fn from(err: PhotoError) -> Self {
        match err {
            PhotoError::ValidationError(msg) => DomainError::Validation {
                code: &PHOTO_VALIDATION,
                reason: msg,
            },
            PhotoError::NotFound { id } => DomainError::NotFound {
                code: &PHOTO_NOT_FOUND,
                resource: "photo",
                id,
            },
            PhotoError::AlreadyDeleted => DomainError::Conflict {
                code: &PHOTO_ALREADY_DELETED,
                reason: "photo is already deleted".into(),
            },
            PhotoError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                expected,
                current: actual,
            },
        }
    }
}

/// Convenience constructors used by the read side (infra) and the API edge.
///
/// These are the *generic* shapes with the generic registry codes; the
/// domain From impls above use the per-context codes.
impl DomainError {
    /// 404 — entity not found (generic code; per-context codes are chosen by
    /// the module From impls). `resource` is a stable slug for logs/tests.
    pub fn not_found(resource: &'static str) -> Self {
        DomainError::NotFound {
            code: &DOMAIN_NOT_FOUND,
            resource,
            id: Uuid::nil(),
        }
    }

    /// 409 — generic state conflict.
    pub fn conflict(reason: impl Into<String>) -> Self {
        DomainError::Conflict {
            code: &DOMAIN_CONFLICT,
            reason: reason.into(),
        }
    }

    /// 503 — generic upstream unavailability.
    pub fn service_unavailable(reason: impl Into<String>) -> Self {
        DomainError::ServiceUnavailable {
            code: &DOMAIN_SERVICE_UNAVAILABLE,
            reason: reason.into(),
        }
    }

    /// 503 — an upstream dependency rejected our credentials (issue #637).
    ///
    /// Use for 401/403/invalid-token responses from Vault (or a future
    /// dependency), never for transient connection/5xx failures. The distinct
    /// variant is what lets a worker treat it as non-retryable.
    pub fn dependency_auth_failed(reason: impl Into<String>) -> Self {
        DomainError::DependencyAuthFailed {
            code: &DEPENDENCY_AUTH_FAILED,
            reason: reason.into(),
        }
    }

    /// 500 — server-side fault (projection/schema drift, internal failures).
    /// `reason` is log-only (http-error-surface spec: internal text never
    /// leaves the server). The code is fixed to `http.internal-error`.
    pub fn internal(reason: impl Into<String>) -> Self {
        DomainError::Internal {
            reason: reason.into(),
        }
    }

    /// 422 — generic domain validation failure.
    pub fn validation(reason: impl Into<String>) -> Self {
        DomainError::Validation {
            code: &DOMAIN_VALIDATION,
            reason: reason.into(),
        }
    }

    /// 403 — generic authorization denial.
    pub fn forbidden(reason: impl Into<String>) -> Self {
        DomainError::Forbidden {
            code: &DOMAIN_FORBIDDEN,
            reason: reason.into(),
        }
    }

    /// The stable problem `code` this error renders (ADR-031 D2).
    ///
    /// The single source of a `DomainError`'s identity: the HTTP boundary
    /// (`crates/api`) and operational consumers — the AI-import attempt
    /// history (issue #639) — read the same registered entry, so a persisted
    /// code can never drift from the problem document the same error renders.
    /// Never localized; `title`/`detail` remain the presentation layer.
    pub fn code(&self) -> &'static ProblemCode {
        match self {
            DomainError::NotFound { code, .. }
            | DomainError::Forbidden { code, .. }
            | DomainError::Validation { code, .. }
            | DomainError::Conflict { code, .. }
            | DomainError::ServiceUnavailable { code, .. }
            | DomainError::DependencyAuthFailed { code, .. } => code,
            DomainError::Internal { .. } => &HTTP_INTERNAL_ERROR,
            DomainError::VersionConflict { .. } => &CONCURRENCY_VERSION_MISMATCH,
            DomainError::AlreadyScheduled { .. } => &SCENE_ALREADY_SCHEDULED,
            DomainError::NotScheduled { .. } => &SCENE_NOT_SCHEDULED,
            DomainError::AlreadyLinked { .. } => &SCENE_SHOOT_ALREADY_LINKED,
            DomainError::ShootingDayWrapped { .. } => &SCENE_SHOOT_SHOOTING_DAY_WRAPPED,
            DomainError::ShootingDayTargetWrapped { .. } => &SHOOTING_DAY_TARGET_WRAPPED,
            DomainError::CategorySeasonMismatch { .. } => &COSTUME_CATEGORY_SEASON_MISMATCH,
        }
    }

    /// Whether a background worker should treat this failure as a transient
    /// condition worth retrying.
    ///
    /// Only [`DomainError::ServiceUnavailable`] is transient. In particular
    /// [`DomainError::DependencyAuthFailed`] is **not**: a rejected credential
    /// is a permanent misconfiguration, and retrying it burns the retry budget
    /// while the cause persists (issue #637). `Conflict` and validation
    /// failures are likewise non-retryable.
    pub const fn is_retryable(&self) -> bool {
        matches!(self, DomainError::ServiceUnavailable { .. })
    }
}

#[cfg(test)]
mod retry_classification_tests {
    use super::DomainError;

    #[test]
    fn only_service_unavailable_is_retryable() {
        assert!(DomainError::service_unavailable("blip").is_retryable());
        // A rejected credential is permanent: retrying burns the budget
        // (issue #637).
        assert!(!DomainError::dependency_auth_failed("invalid token").is_retryable());
        assert!(!DomainError::conflict("lost claim").is_retryable());
        assert!(!DomainError::validation("bad input").is_retryable());
    }

    #[test]
    fn dependency_auth_failed_uses_the_registered_code() {
        let error = DomainError::dependency_auth_failed("invalid token");
        let DomainError::DependencyAuthFailed { code, .. } = error else {
            panic!("expected DependencyAuthFailed");
        };
        assert_eq!(code.code, "dependency.auth-failed");
        assert_eq!(code.status, 503);
    }

    #[test]
    fn code_matches_the_registry_entry_for_every_shape() {
        // Variants that carry their entry.
        assert_eq!(
            DomainError::service_unavailable("blip").code().code,
            "domain.service-unavailable"
        );
        assert_eq!(
            DomainError::dependency_auth_failed("token").code().code,
            "dependency.auth-failed"
        );
        assert_eq!(DomainError::conflict("x").code().code, "domain.conflict");
        assert_eq!(
            DomainError::not_found("scene").code().code,
            "domain.not-found"
        );
        // Variants whose code is fixed by construction.
        assert_eq!(
            DomainError::internal("boom").code().code,
            "http.internal-error"
        );
        assert_eq!(
            DomainError::VersionConflict {
                expected: super::AggregateVersion::INITIAL,
                current: super::AggregateVersion::INITIAL,
            }
            .code()
            .code,
            "concurrency.version-mismatch"
        );
    }
}
