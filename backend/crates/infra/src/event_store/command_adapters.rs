// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0 (opencode-go)

//! `kameo_es` write adapters implementing the `core` command ports.
//!
//! Every adapter owns a clone of the shared `CommandService`. It translates a
//! `core` command into `SceneAggregate::execute(...)` / `ExpectedVersion` calls
//! against SierraDB and maps the reply back to `DomainError`.
//!
//! Adapters are write-side only: they never query read-model projections.
//! The `series_id` for the `EventMetadata` audit trail (the audit projector
//! keys on `series_id`) is carried directly on each command struct and
//! resolved at the API edge by the handlers (the read-model boundary).
//!
//! ## Provenance conventions
//!
//! - **Human**: All dispatches from `*CommandsImpl` adapters use
//!   `Provenance::Human` with `actor: Some(user_id)`.
//! - **Saga**: Named sagas dispatch directly via `Aggregate::execute(...)`
//!   with `Provenance::Saga("<StableName>")` and `actor: None`.
//! - **System**: Any future system-initiated dispatch (neither human nor named
//!   saga) must use `Provenance::System` with `actor: None`.

use breakdown_core::ai::aggregate::AiConfig;
use breakdown_core::ai::commands::{CreateAiConfig, RevokeAiConfig, UpdateAiConfig};
use breakdown_core::ai::ports::AiConfigCommands;
use breakdown_core::block::aggregate::BlockAggregate;
use breakdown_core::block::commands::{CreateBlock, UpdateBlockTimeSpan};
use breakdown_core::block::ports::BlockCommands;
use breakdown_core::character::aggregate::CharacterAggregate;
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::ports::CharacterCommands;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume::commands::{
    AddCostumeToSeason, AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto,
    RemoveCostumeFromSeason, RemoveDetail, SetCostumeCategory, UnassignCostume, UnlinkPhoto,
    UpdateCostumeDetail, UpdateCostumeNotes,
};
use breakdown_core::costume::ports::CostumeCommands;
use breakdown_core::costume_category::aggregate::CostumeCategoryAggregate;
use breakdown_core::costume_category::commands::{
    ArchiveCostumeCategory, CreateCostumeCategory, RenameCostumeCategory, ReorderCostumeCategory,
};
use breakdown_core::costume_category::ports::CostumeCategoryCommands;
use breakdown_core::episode::aggregate::EpisodeAggregate;
use breakdown_core::episode::commands::{CreateEpisode, RenameEpisode};
use breakdown_core::episode::ports::EpisodeCommands;
use breakdown_core::error::DomainError;
use breakdown_core::membership::aggregate::BlockMembership;
use breakdown_core::membership::commands::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, RemoveMember,
};
use breakdown_core::membership::ports::MembershipCommands;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::commands::{
    DeletePhoto, GenerateVariant, MarkVariantFailed, NormalizeOriginal, UploadPhoto,
};
use breakdown_core::photo::ports::PhotoCommands;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::commands::{
    AddCostumeBeat, AssignCharacter, CreateScene, RemoveCharacter, RemoveCostumeBeat,
    ScheduleSceneOnShootingDay, UnscheduleSceneFromShootingDay, UpdateCostumeBeat,
    UpdateSceneDetails,
};
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
use breakdown_core::scene_shoot::commands::{
    AddSceneShootNote, FinishSceneShoot, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote,
};
use breakdown_core::scene_shoot::ports::SceneShootCommands;
use breakdown_core::season::aggregate::SeasonAggregate;
use breakdown_core::season::commands::{ArchiveSeason, CreateSeason, RenameSeason};
use breakdown_core::season::ports::SeasonCommands;
use breakdown_core::settings::aggregate::SettingsAggregate;
use breakdown_core::settings::commands::{
    CreateCredentialBinding, RevokeCredential, RotateCredentialBinding,
};
use breakdown_core::settings::ports::SettingsCommands;
use breakdown_core::shared::{
    AggregateVersion, EventMetadata, Provenance, SceneShootId, ShootingDayId, UserId,
};
use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;
use breakdown_core::shooting_day::commands::{
    ArchiveShootingDay, CreateShootingDay, EnsureShootingDayOpen, RenameShootingDay,
    ReorderShootingDay, RescheduleShootingDay, WrapShootingDay,
};
use breakdown_core::shooting_day::error::ShootingDayError;
use breakdown_core::shooting_day::ports::ShootingDayCommands;
use kameo_es::ConnectionPool;
use kameo_es::command_service::{CommandService, ExecuteExt, ExecuteResult};
use kameo_es::error::ExecuteError;
use sierradb_client::{CurrentVersion, ExpectedVersion};
use uuid::Uuid;

use crate::reservations::event::{
    block_number_key, episode_number_key, scene_shoot_pair_key, season_number_key,
};
use crate::reservations::store::{ReservationClaim, ReservationStore};

// ADR-036: the four migrated invariants share their registered problem codes
// between the API-edge advisory pre-check (handlers) and this atomic
// write-boundary reservation — one stable branch per client code.
use breakdown_core::error_registry::{
    BLOCK_NUMBER_ALREADY_EXISTS, EPISODE_NUMBER_ALREADY_EXISTS, SCENE_SHOOT_PAIR_ALREADY_EXISTS,
    SEASON_NUMBER_ALREADY_EXISTS,
};

/// ADR-036 §3.1/§3.2 — compensation policy for claimed creates.
///
/// - `ExecuteError::Handle` (the aggregate rejected the command BEFORE any
///   append): nothing reached the aggregate stream — release the claim inline
///   (best-effort CAS; a failed release is logged and the reaper owns the
///   orphan, §3.2).
/// - `IncorrectExpectedVersion` (the aggregate stream exists → the claim may
///   already be realized) or any database failure (append state unknown):
///   releasing locally could open a still-owned key and re-widen the exact
///   race this ADR closes — the claim stays held and the reaper resolves it
///   by probing the event store (§3.2).
///
/// Never masks the original error; the create failure propagates unchanged.
async fn compensate_create_claim<ResultValue, Err>(
    store: &ReservationStore,
    claim: &ReservationClaim,
    result: &Result<ResultValue, ExecuteError<Err>>,
) {
    if let Err(ExecuteError::Handle(_)) = result
        && let Err(release_err) = store
            .release(&claim.key, claim.aggregate_id, claim.claim_version)
            .await
    {
        tracing::warn!(
            key = %claim.key,
            release_error = %release_err,
            "reservation release failed after handle-rejected create; the reaper will release the orphan claim (ADR-036 §3.1)",
        );
    }
}

/// ADR-036 §2 — reserve the create key for a reservation-protected create
/// command. The returned claim must accompany the aggregate append so a
/// failed create can release its claim.
async fn reserve_create_claim(
    store: &ReservationStore,
    key: &str,
    aggregate_id: Uuid,
    conflict: DomainError,
) -> Result<ReservationClaim, DomainError> {
    store.reserve(key, aggregate_id, conflict).await
}

use async_trait::async_trait;

/// Command adapter for the Scene aggregate.
#[derive(Clone, Debug)]
pub struct SceneCommandsImpl {
    cmd_service: CommandService,
}

impl SceneCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl SceneCommands for SceneCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateScene,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_executed(id, result)
    }

    async fn update_details(
        &self,
        actor: UserId,
        cmd: UpdateSceneDetails,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn assign_character(
        &self,
        actor: UserId,
        cmd: AssignCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn remove_character(
        &self,
        actor: UserId,
        cmd: RemoveCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn add_costume_beat(
        &self,
        actor: UserId,
        cmd: AddCostumeBeat,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn update_costume_beat(
        &self,
        actor: UserId,
        cmd: UpdateCostumeBeat,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn remove_costume_beat(
        &self,
        actor: UserId,
        cmd: RemoveCostumeBeat,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn schedule_on_shooting_day(
        &self,
        actor: UserId,
        cmd: ScheduleSceneOnShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn unschedule_from_shooting_day(
        &self,
        actor: UserId,
        cmd: UnscheduleSceneFromShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the `ShootingDay` aggregate.
#[derive(Clone, Debug)]
pub struct ShootingDayCommandsImpl {
    cmd_service: CommandService,
    /// Per-day wrap-finality lock (PR #389 review follow-up): the wrap
    /// transition holds it across its append so no frozen SceneShoot
    /// mutation can interleave with the wrap on the same day.
    finality_gate: crate::event_store::WrapFinalityGate,
}

impl ShootingDayCommandsImpl {
    pub fn new(
        cmd_service: CommandService,
        finality_gate: crate::event_store::WrapFinalityGate,
    ) -> Self {
        Self {
            cmd_service,
            finality_gate,
        }
    }
}

impl ShootingDayCommands for ShootingDayCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateShootingDay,
    ) -> Result<(ShootingDayId, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = cmd.series_id;
        let result = ShootingDayAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_executed(id, result)
    }

    async fn rename(
        &self,
        actor: UserId,
        cmd: RenameShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = ShootingDayAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn reschedule(
        &self,
        actor: UserId,
        cmd: RescheduleShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = ShootingDayAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn reorder(
        &self,
        actor: UserId,
        cmd: ReorderShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = ShootingDayAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn archive(
        &self,
        actor: UserId,
        cmd: ArchiveShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = ShootingDayAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn wrap(
        &self,
        actor: UserId,
        cmd: WrapShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize the wrap append against frozen SceneShoot mutations on
        // this day (distributed per-day advisory lock, PR #389 review
        // follow-up): after `wrap` completes, no execution mutation for the
        // day can still be appended.
        let _day_lock = self.finality_gate.lock_day(cmd.id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = ShootingDayAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Settings aggregate.
#[derive(Clone, Debug)]
pub struct SettingsCommandsImpl {
    cmd_service: CommandService,
}

impl SettingsCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

#[async_trait]
impl SettingsCommands for SettingsCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCredentialBinding,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let result = SettingsAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id: None,
            })
            .await;
        map_executed(id, result)
    }

    async fn rotate(
        &self,
        actor: UserId,
        cmd: RotateCredentialBinding,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = SettingsAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id: None,
            })
            .await;
        map_version_only(result)
    }

    async fn revoke(
        &self,
        actor: UserId,
        cmd: RevokeCredential,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = SettingsAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id: None,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Character aggregate.
#[derive(Clone, Debug)]
pub struct CharacterCommandsImpl {
    cmd_service: CommandService,
}

impl CharacterCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl CharacterCommands for CharacterCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCharacter,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = cmd.series_id;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_executed(id, result)
    }

    async fn update_measurements(
        &self,
        actor: UserId,
        cmd: UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn update_contact_info(
        &self,
        actor: UserId,
        cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Costume aggregate.
#[derive(Clone, Debug)]
pub struct CostumeCommandsImpl {
    cmd_service: CommandService,
}

impl CostumeCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl CostumeCommands for CostumeCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCostume,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        // The series is not a costume attribute — it is audit metadata only,
        // resolved at the API edge from the repertoire season's projection
        // (issue #453). A costume created without a season carries `None`.
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_executed(id, result)
    }

    async fn update_notes(
        &self,
        actor: UserId,
        cmd: UpdateCostumeNotes,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn assign_to_character(
        &self,
        actor: UserId,
        cmd: AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn unassign(
        &self,
        actor: UserId,
        cmd: UnassignCostume,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn add_to_season(
        &self,
        actor: UserId,
        cmd: AddCostumeToSeason,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        // `series_id` is audit metadata resolved at the API edge from the
        // target season's projection (CQRS boundary: no read-model lookup
        // here) and is never allowed to block the command.
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        // Issue #534 state-based no-op: re-adding a season already in the
        // repertoire emits NO event — `ExecuteResult::Executed(vec![])`,
        // which `map_version_only` would turn into a 409. The version fence
        // matched, so the aggregate is exactly at the caller's version: this
        // is a success and the version is unchanged (issue #515 lesson).
        match result {
            Ok(ExecuteResult::Executed(events)) if events.is_empty() => Ok(version),
            other => map_version_only(other),
        }
    }

    async fn remove_from_season(
        &self,
        actor: UserId,
        cmd: RemoveCostumeFromSeason,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        // Idempotent mirror of `add_to_season`: removing a season that is
        // not in the repertoire emits no event.
        match result {
            Ok(ExecuteResult::Executed(events)) if events.is_empty() => Ok(version),
            other => map_version_only(other),
        }
    }

    async fn add_detail(
        &self,
        actor: UserId,
        cmd: AddDetail,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn update_detail(
        &self,
        actor: UserId,
        cmd: UpdateCostumeDetail,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        // `series_id` is audit metadata resolved at the API edge (CQRS
        // boundary: no read-model lookup here) and is never allowed to
        // block the command.
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn remove_detail(
        &self,
        actor: UserId,
        cmd: RemoveDetail,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn set_category(
        &self,
        actor: UserId,
        cmd: SetCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        // Issue #543 state-based no-op: the aggregate emits NO event when the
        // target category equals the current one (re-dispatch, or clearing an
        // already-empty costume). kameo_es reports that as
        // `ExecuteResult::Executed(vec![])` — NOT as `Idempotent` — which
        // `map_version_only` would turn into a 409 "command produced no
        // events". The version fence matched, so the aggregate is exactly at
        // the caller's version: this is a success and the version is
        // unchanged (CodeRabbit review).
        match result {
            Ok(ExecuteResult::Executed(events)) if events.is_empty() => Ok(version),
            other => map_version_only(other),
        }
    }

    async fn link_photo(
        &self,
        actor: UserId,
        cmd: LinkPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn unlink_photo(
        &self,
        actor: UserId,
        cmd: UnlinkPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Season aggregate.
#[derive(Clone, Debug)]
pub struct SeasonCommandsImpl {
    cmd_service: CommandService,
    /// ADR-036: `(series_id, number)` claim store; built from the same pooled
    /// SierraDB connection the CommandService dispatches over.
    reservations: ReservationStore,
}

impl SeasonCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self {
            reservations: ReservationStore::new(ConnectionPool::from(cmd_service.conn())),
            cmd_service,
        }
    }
}

impl SeasonCommands for SeasonCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateSeason,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = Some(cmd.series_id);
        let claim = reserve_create_claim(
            &self.reservations,
            &season_number_key(cmd.series_id.0, cmd.number),
            id,
            DomainError::Conflict {
                code: &SEASON_NUMBER_ALREADY_EXISTS,
                reason: "season number already taken".into(),
            },
        )
        .await?;
        let result = SeasonAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        compensate_create_claim(&self.reservations, &claim, &result).await;
        map_executed(id, result)
    }

    async fn rename(
        &self,
        actor: UserId,
        cmd: RenameSeason,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SeasonAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn archive(
        &self,
        actor: UserId,
        cmd: ArchiveSeason,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SeasonAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Block aggregate.
#[derive(Clone, Debug)]
pub struct BlockCommandsImpl {
    cmd_service: CommandService,
    /// ADR-036: `(series_id, number)` claim store.
    reservations: ReservationStore,
}

impl BlockCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self {
            reservations: ReservationStore::new(ConnectionPool::from(cmd_service.conn())),
            cmd_service,
        }
    }
}

impl BlockCommands for BlockCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateBlock,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = Some(cmd.series_id);
        let claim = reserve_create_claim(
            &self.reservations,
            &block_number_key(cmd.series_id.0, cmd.number),
            id,
            DomainError::Conflict {
                code: &BLOCK_NUMBER_ALREADY_EXISTS,
                reason: "block number already taken".into(),
            },
        )
        .await?;
        let result = BlockAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        compensate_create_claim(&self.reservations, &claim, &result).await;
        map_executed(id, result)
    }

    async fn update_time_span(
        &self,
        actor: UserId,
        cmd: UpdateBlockTimeSpan,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = BlockAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Episode aggregate.
#[derive(Clone, Debug)]
pub struct EpisodeCommandsImpl {
    cmd_service: CommandService,
    /// ADR-036: `(series_id, number)` claim store — this closes the
    /// pre-check-to-append race on BOTH write paths (manual `POST /episodes`
    /// and the AI-apply worker call `EpisodeCommands::create`).
    reservations: ReservationStore,
}

impl EpisodeCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self {
            reservations: ReservationStore::new(ConnectionPool::from(cmd_service.conn())),
            cmd_service,
        }
    }
}

impl EpisodeCommands for EpisodeCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateEpisode,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = Some(cmd.series_id);
        let claim = reserve_create_claim(
            &self.reservations,
            &episode_number_key(cmd.series_id.0, cmd.number),
            id,
            DomainError::Conflict {
                code: &EPISODE_NUMBER_ALREADY_EXISTS,
                reason: "episode number already taken".into(),
            },
        )
        .await?;
        let result = EpisodeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        compensate_create_claim(&self.reservations, &claim, &result).await;
        map_executed(id, result)
    }

    async fn rename(
        &self,
        actor: UserId,
        cmd: RenameEpisode,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = EpisodeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the membership `BlockMembership` aggregate.
///
/// Every command is dispatched with `ExpectedVersion::Any` (the aggregate
/// enforces invitation/role/membership invariants itself) and carries the
/// authenticated `actor` as `kameo_es` command `Metadata` for audit (Decision 6).
/// The `series_id` is resolved from the targeted block's season.
#[derive(Clone, Debug)]
pub struct MembershipCommandsImpl {
    cmd_service: CommandService,
}

impl MembershipCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

#[async_trait]
impl MembershipCommands for MembershipCommandsImpl {
    async fn invite(&self, actor: UserId, cmd: InviteMember) -> Result<(), DomainError> {
        let series_id = Some(cmd.series_id);
        let result = BlockMembership::execute(&self.cmd_service, cmd.block_id.0, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        let _ = map_executed_result(Uuid::nil(), result)?;
        Ok(())
    }

    async fn accept_invitation(
        &self,
        actor: UserId,
        cmd: AcceptInvitation,
    ) -> Result<(), DomainError> {
        let series_id = Some(cmd.series_id);
        let result = BlockMembership::execute(&self.cmd_service, cmd.block_id.0, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        let _ = map_executed_result(Uuid::nil(), result)?;
        Ok(())
    }

    async fn grant_role(&self, actor: UserId, cmd: GrantRole) -> Result<(), DomainError> {
        let series_id = Some(cmd.series_id);
        let result = BlockMembership::execute(&self.cmd_service, cmd.block_id.0, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        let _ = map_executed_result(Uuid::nil(), result)?;
        Ok(())
    }

    async fn remove_member(&self, actor: UserId, cmd: RemoveMember) -> Result<(), DomainError> {
        let series_id = Some(cmd.series_id);
        let result = BlockMembership::execute(&self.cmd_service, cmd.block_id.0, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        let _ = map_executed_result(Uuid::nil(), result)?;
        Ok(())
    }

    async fn leave_block(&self, actor: UserId, cmd: LeaveBlock) -> Result<(), DomainError> {
        let series_id = Some(cmd.series_id);
        let result = BlockMembership::execute(&self.cmd_service, cmd.block_id.0, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        let _ = map_executed_result(Uuid::nil(), result)?;
        Ok(())
    }

    async fn bootstrap_owner(&self, actor: UserId, cmd: BootstrapOwner) -> Result<(), DomainError> {
        let series_id = Some(cmd.series_id);
        let result = BlockMembership::execute(&self.cmd_service, cmd.block_id.0, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        let _ = map_executed_result(Uuid::nil(), result)?;
        Ok(())
    }
}

/// Command adapter for the CostumeCategory aggregate.
#[derive(Clone, Debug)]
pub struct CostumeCategoryCommandsImpl {
    cmd_service: CommandService,
}

impl CostumeCategoryCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl CostumeCategoryCommands for CostumeCategoryCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCostumeCategory,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = cmd.series_id;
        let result = CostumeCategoryAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_executed(id, result)
    }

    async fn rename(
        &self,
        actor: UserId,
        cmd: RenameCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeCategoryAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn reorder(
        &self,
        actor: UserId,
        cmd: ReorderCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeCategoryAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn archive(
        &self,
        actor: UserId,
        cmd: ArchiveCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = CostumeCategoryAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Photo aggregate.
#[derive(Clone, Debug)]
pub struct PhotoCommandsImpl {
    cmd_service: CommandService,
}

impl PhotoCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

#[async_trait]
impl PhotoCommands for PhotoCommandsImpl {
    async fn upload(
        &self,
        actor: UserId,
        cmd: UploadPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let series_id = cmd.series_id;
        let result = PhotoAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn normalize_original(
        &self,
        actor: UserId,
        cmd: NormalizeOriginal,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = PhotoAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn generate_variant(
        &self,
        actor: UserId,
        cmd: GenerateVariant,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = PhotoAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn mark_variant_failed(
        &self,
        actor: UserId,
        cmd: MarkVariantFailed,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = PhotoAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn delete(
        &self,
        actor: UserId,
        cmd: DeletePhoto,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = PhotoAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}
/// Command adapter for the SceneShoot aggregate.
#[derive(Clone, Debug)]
pub struct SceneShootCommandsImpl {
    cmd_service: CommandService,
    /// Per-day wrap-finality lock (PR #389 review follow-up): serializes the
    /// [probe → append] critical section of every frozen command against the
    /// day's `WrapShootingDay` append.
    finality_gate: crate::event_store::WrapFinalityGate,
    /// ADR-036: `(scene_id, shooting_day_id)` pair claim store.
    reservations: ReservationStore,
}

impl SceneShootCommandsImpl {
    pub fn new(
        cmd_service: CommandService,
        finality_gate: crate::event_store::WrapFinalityGate,
    ) -> Self {
        Self {
            reservations: ReservationStore::new(ConnectionPool::from(cmd_service.conn())),
            cmd_service,
            finality_gate,
        }
    }

    /// Write-side wrap-finality gate (PR #389 review, issue #376).
    ///
    /// Dispatches the zero-event [`EnsureShootingDayOpen`] command against
    /// the ShootingDay **event stream** — the authoritative write-side
    /// state — so execution transitions are frozen on wrapped days even
    /// while the read-model projection still lags. This is a stream replay
    /// on the command path, **not** a read-model projection query (CQRS
    /// boundary hard rule).
    ///
    /// The check runs **under the per-day wrap-finality advisory lock**, so
    /// no `WrapShootingDay` append can interleave between this probe and
    /// the SceneShoot append (see [`crate::event_store::WrapFinalityGate`]).
    async fn ensure_day_open(&self, day_id: ShootingDayId) -> Result<(), DomainError> {
        let result = ShootingDayAggregate::execute(
            &self.cmd_service,
            day_id,
            EnsureShootingDayOpen { id: day_id },
        )
        .expected_version(ExpectedVersion::Any)
        .await;
        match result {
            // Open day: no events emitted, probe succeeded.
            Ok(_) => Ok(()),
            Err(ExecuteError::Handle(ShootingDayError::Wrapped { id })) => {
                Err(DomainError::ShootingDayWrapped {
                    shooting_day_id: id.0,
                })
            }
            Err(ExecuteError::Handle(err)) => Err(err.into()),
            Err(err) => Err(DomainError::conflict(err.to_string())),
        }
    }
}

impl SceneShootCommands for SceneShootCommandsImpl {
    async fn plan(
        &self,
        actor: UserId,
        cmd: PlanSceneShoot,
    ) -> Result<(SceneShootId, AggregateVersion), DomainError> {
        let id = cmd.id;
        let series_id = cmd.series_id;
        let claim = reserve_create_claim(
            &self.reservations,
            &scene_shoot_pair_key(cmd.scene_id, cmd.shooting_day_id.0),
            id.0,
            DomainError::Conflict {
                code: &SCENE_SHOOT_PAIR_ALREADY_EXISTS,
                reason: "scene is already scheduled on this shooting day".into(),
            },
        )
        .await?;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        compensate_create_claim(&self.reservations, &claim, &result).await;
        map_executed(id, result)
    }

    async fn replan(
        &self,
        actor: UserId,
        cmd: ReplanSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn start(
        &self,
        actor: UserId,
        cmd: StartSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn set_actual_order(
        &self,
        actor: UserId,
        cmd: SetActualOrder,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn finish(
        &self,
        actor: UserId,
        cmd: FinishSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn skip(
        &self,
        actor: UserId,
        cmd: SkipSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn add_note(
        &self,
        actor: UserId,
        cmd: AddSceneShootNote,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn update_note(
        &self,
        actor: UserId,
        cmd: UpdateSceneShootNote,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn remove_note(
        &self,
        actor: UserId,
        cmd: RemoveSceneShootNote,
    ) -> Result<AggregateVersion, DomainError> {
        // Serialize [probe -> append] against the day's wrap transition
        // (distributed per-day advisory lock, PR #389 review follow-up).
        let _day_lock = self.finality_gate.lock_day(cmd.shooting_day_id).await?;
        self.ensure_day_open(cmd.shooting_day_id).await?;
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn link_continuity_photo(
        &self,
        actor: UserId,
        cmd: LinkContinuityPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }

    async fn unlink_continuity_photo(
        &self,
        actor: UserId,
        cmd: UnlinkContinuityPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let series_id = cmd.series_id;
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
        map_version_only(result)
    }
}

pub fn map_version_only<Ent, Err>(
    result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
) -> Result<AggregateVersion, DomainError>
where
    Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
    Err: Into<DomainError> + std::fmt::Debug + Send + Sync + 'static,
{
    let (id, version) = map_executed_result(Uuid::nil(), result)?;
    let _ = id;
    Ok(version)
}

pub fn map_executed<Ent, Err, Id>(
    id: Id,
    result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
) -> Result<(Id, AggregateVersion), DomainError>
where
    Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
    Err: Into<DomainError> + std::fmt::Debug + Send + Sync + 'static,
{
    map_executed_result(id, result)
}

/// Translate a SierraDB stream version (0-based) to the canonical domain version (1-based).
/// `domain_version = stream_version + 1`
#[must_use]
pub fn stream_to_domain(stream_version: u64) -> AggregateVersion {
    AggregateVersion(stream_version + 1)
}

/// Translate the canonical domain version (1-based) back to a SierraDB stream version (0-based).
/// Returns `None` for domain version 0 (no events → no stream version).
#[must_use]
pub fn domain_to_stream(domain_version: AggregateVersion) -> Option<u64> {
    if domain_version.0 == 0 {
        None
    } else {
        Some(domain_version.0 - 1)
    }
}

/// Check that a domain version is non-zero and translate it to a SierraDB stream
/// version.  Combines [`check_nonzero_version`] + [`domain_to_stream`] so the
/// invariant (version > 0 ⇒ stream version is `Some`) is enforced by the type
/// system rather than by a comment-driven `expect`.  Returns
/// `DomainError::VersionConflict` for version 0.
pub fn domain_to_stream_checked(version: AggregateVersion) -> Result<u64, DomainError> {
    if version.0 == 0 {
        Err(DomainError::VersionConflict {
            expected: AggregateVersion(0),
            current: AggregateVersion(0),
        })
    } else {
        Ok(version.0 - 1)
    }
}

pub fn map_executed_result<Ent, Err, Id>(
    id: Id,
    result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
) -> Result<(Id, AggregateVersion), DomainError>
where
    Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
    Err: Into<DomainError> + std::fmt::Debug + Send + Sync + 'static,
{
    match result {
        Ok(ExecuteResult::Executed(events)) => {
            let version = events
                .last()
                .map(|e| stream_to_domain(e.stream_version))
                .ok_or_else(|| DomainError::conflict("command produced no events"))?;
            Ok((id, version))
        }
        Ok(ExecuteResult::Idempotent { current_version }) => {
            Ok((id, version_from_current(current_version)))
        }
        Ok(ExecuteResult::PendingTransaction { .. }) => {
            Err(DomainError::conflict("pending transaction not supported"))
        }
        Err(ExecuteError::Handle(err)) => Err(err.into()),
        Err(ExecuteError::IncorrectExpectedVersion {
            stream_id: _,
            current,
            ..
        }) => Err(DomainError::VersionConflict {
            expected: AggregateVersion(0),
            current: version_from_current(current),
        }),
        Err(err) => Err(DomainError::conflict(err.to_string())),
    }
}

/// Map `CurrentVersion` to the canonical domain version.
/// `Empty` (no events) → `AggregateVersion(0)` — no domain version yet.
/// `Current(v)` (SierraDB reports version `v`) → `AggregateVersion(v + 1)`.
pub fn version_from_current(current: CurrentVersion) -> AggregateVersion {
    match current {
        CurrentVersion::Current(v) => stream_to_domain(v),
        CurrentVersion::Empty => AggregateVersion(0),
    }
}

/// Map `ExpectedVersion` to the canonical domain version.
/// Only used in error context to inform the caller what they supplied.
#[allow(dead_code)] // reserved for future error reporting
pub fn version_from_expected(expected: ExpectedVersion) -> AggregateVersion {
    match expected {
        ExpectedVersion::Exact(v) => AggregateVersion(v),
        ExpectedVersion::Empty => AggregateVersion::INITIAL,
        _ => AggregateVersion::INITIAL,
    }
}

/// Check that a domain version is non-zero (valid for update operations).
/// Returns `DomainError::VersionConflict` when `version.0 == 0`.
pub fn check_nonzero_version(version: AggregateVersion) -> Result<(), DomainError> {
    if version.0 == 0 {
        Err(DomainError::VersionConflict {
            expected: AggregateVersion(0),
            current: AggregateVersion(0),
        })
    } else {
        Ok(())
    }
}

/// Command adapter for the dedicated AI configuration aggregate.
#[derive(Clone, Debug)]
pub struct AiConfigCommandsImpl {
    cmd_service: CommandService,
}

impl AiConfigCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

#[async_trait]
impl AiConfigCommands for AiConfigCommandsImpl {
    async fn create(
        &self,
        actor: UserId,
        command: CreateAiConfig,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = command.id;
        let result = AiConfig::execute(&self.cmd_service, id, command)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id: None,
            })
            .await;
        map_executed(id, result)
    }

    async fn update(
        &self,
        actor: UserId,
        command: UpdateAiConfig,
    ) -> Result<AggregateVersion, DomainError> {
        let id = command.id;
        let version = command.version;
        check_nonzero_version(version)?;
        let result = AiConfig::execute(&self.cmd_service, id, command)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id: None,
            })
            .await;
        map_version_only(result)
    }

    async fn revoke(
        &self,
        actor: UserId,
        command: RevokeAiConfig,
    ) -> Result<AggregateVersion, DomainError> {
        let id = command.id;
        let version = command.version;
        check_nonzero_version(version)?;
        let result = AiConfig::execute(&self.cmd_service, id, command)
            .expected_version(ExpectedVersion::Exact(domain_to_stream_checked(version)?))
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id: None,
            })
            .await;
        map_version_only(result)
    }
}

#[cfg(test)]
mod tests {
    // Test code lifts the workspace clippy panics/unwrap lints via
    // `#![cfg_attr(test, allow(...))]` in `crates/infra/src/lib.rs`.

    use breakdown_core::shared::AggregateVersion;

    use super::domain_to_stream_checked;

    /// Kills the five `domain_to_stream_checked` mutants: `==`→`!=`,
    /// `Ok(0)`/`Ok(1)`, `-`→`+`/`/`. The function must reject version 0 with
    /// a `VersionConflict` and return `version - 1` for any version > 0.
    #[test]
    fn domain_to_stream_checked_rejects_zero_and_decrements() {
        // Version 0 → Err (kills the ==→!= mutant, which would return Ok).
        let err =
            domain_to_stream_checked(AggregateVersion(0)).expect_err("version 0 must be rejected");
        assert_eq!(
            err,
            breakdown_core::error::DomainError::VersionConflict {
                expected: AggregateVersion(0),
                current: AggregateVersion(0),
            }
        );

        // INITIAL (1) → Ok(0). Kills Ok(1) and the -→+ mutant (which gives 2).
        assert_eq!(
            domain_to_stream_checked(AggregateVersion::INITIAL).expect("INITIAL ok"),
            0
        );

        // Arbitrary version → Ok(version - 1). Kills Ok(0), Ok(1), -→+, -→/.
        assert_eq!(
            domain_to_stream_checked(AggregateVersion(42)).expect("42 ok"),
            41
        );
    }
}
