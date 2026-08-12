// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

use thiserror::Error;
use uuid::Uuid;

use crate::ai::error::AiConfigError;
use crate::block::error::BlockError;
use crate::character::error::CharacterError;
use crate::costume::error::CostumeError;
use crate::costume_category::error::CostumeCategoryError;
use crate::episode::error::EpisodeError;
use crate::error_registry::{
    AI_CONFIG_ALREADY_REVOKED, AI_CONFIG_EMPTY_MODEL, AI_CONFIG_EMPTY_PROMPT,
    AI_CONFIG_EMPTY_PROVIDER, AI_CONFIG_EMPTY_VAULT_KEY, AI_CONFIG_NOT_FOUND,
    AI_CONFIG_PROVIDER_MISMATCH, BLOCK_NOT_FOUND, CHARACTER_NOT_FOUND, CHARACTER_VALIDATION,
    COSTUME_CATEGORY_ARCHIVED, COSTUME_CATEGORY_VALIDATION, COSTUME_NOT_FOUND, COSTUME_VALIDATION,
    DOMAIN_CONFLICT, DOMAIN_FORBIDDEN, DOMAIN_NOT_FOUND, DOMAIN_SERVICE_UNAVAILABLE,
    DOMAIN_VALIDATION, EPISODE_NOT_FOUND, MEMBERSHIP_ALREADY_INVITED,
    MEMBERSHIP_BOOTSTRAP_NOT_ALLOWED, MEMBERSHIP_MISSING_ACTOR, MEMBERSHIP_NO_PENDING_INVITATION,
    MEMBERSHIP_NOT_ACTIVE_MEMBER, MEMBERSHIP_NOT_FOUND, PHOTO_ALREADY_DELETED, PHOTO_NOT_FOUND,
    PHOTO_VALIDATION, ProblemCode, SCENE_CHARACTER_ALREADY_ASSIGNED, SCENE_CHARACTER_NOT_FOUND,
    SCENE_NOT_FOUND, SCENE_SHOOT_ALREADY_STARTED, SCENE_SHOOT_NOT_FOUND,
    SCENE_SHOOT_NOTE_NOT_FOUND, SCENE_SHOOT_PAIR_ALREADY_EXISTS, SCENE_SHOOT_PLANNED_ORDER_FROZEN,
    SCENE_SHOOT_TERMINAL_STATE, SCENE_SHOOT_VALIDATION, SCENE_VALIDATION, SEASON_NOT_FOUND,
    SETTINGS_ALREADY_REVOKED, SETTINGS_EMPTY_PROVIDER, SETTINGS_EMPTY_VAULT_KEY,
    SETTINGS_NOT_FOUND, SETTINGS_PROVIDER_MISMATCH, SHOOTING_DAY_ARCHIVED,
    SHOOTING_DAY_DUPLICATE_ORDER_KEY, SHOOTING_DAY_NOT_FOUND, SHOOTING_DAY_VALIDATION,
};
use crate::membership::error::MembershipError;
use crate::photo::error::PhotoError;
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

    /// Costume already assigned to a character (409, `costume.already-assigned`).
    /// `character_id` is S1 — rendered only after the handler's authz gate.
    #[error("costume is already assigned to character {character_id}")]
    AlreadyAssigned { character_id: Uuid },

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
            SceneError::CharacterAlreadyAssigned => DomainError::Conflict {
                code: &SCENE_CHARACTER_ALREADY_ASSIGNED,
                reason: "character already assigned to this scene".into(),
            },
            SceneError::AlreadyScheduled { shooting_day_id } => DomainError::AlreadyScheduled {
                shooting_day_id: shooting_day_id.0,
            },
            SceneError::NotScheduled { shooting_day_id } => DomainError::NotScheduled {
                shooting_day_id: shooting_day_id.0,
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
        }
    }
}

impl From<CostumeError> for DomainError {
    fn from(err: CostumeError) -> Self {
        match err {
            CostumeError::ValidationError(msg) => DomainError::Validation {
                code: &COSTUME_VALIDATION,
                reason: msg,
            },
            CostumeError::NotFound { id } => DomainError::NotFound {
                code: &COSTUME_NOT_FOUND,
                resource: "costume",
                id,
            },
            CostumeError::AlreadyAssigned { assigned_to } => DomainError::AlreadyAssigned {
                character_id: assigned_to,
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
            ShootingDayError::ArchivedCannotBeMutated { .. } => DomainError::Conflict {
                code: &SHOOTING_DAY_ARCHIVED,
                reason: "shooting day is archived and cannot be mutated".into(),
            },
            ShootingDayError::DuplicateOrderKey(key) => DomainError::Conflict {
                code: &SHOOTING_DAY_DUPLICATE_ORDER_KEY,
                reason: format!("order key {key} already exists for this episode"),
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
}
