// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)

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
    AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, RemoveDetail, UnassignCostume,
    UnlinkPhoto, UpdateCostumeNotes,
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
    AssignCharacter, CreateScene, RemoveCharacter, ScheduleSceneOnShootingDay,
    UnscheduleSceneFromShootingDay, UpdateSceneDetails,
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
use breakdown_core::season::commands::{CreateSeason, RenameSeason};
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
    ArchiveShootingDay, CreateShootingDay, RenameShootingDay, ReorderShootingDay,
    RescheduleShootingDay, WrapShootingDay,
};
use breakdown_core::shooting_day::ports::ShootingDayCommands;
use kameo_es::command_service::{CommandService, ExecuteExt, ExecuteResult};
use kameo_es::error::ExecuteError;
use sierradb_client::{CurrentVersion, ExpectedVersion};
use uuid::Uuid;

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
}

impl ShootingDayCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
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
        // A freshly created costume has no character association yet, so the
        // series is genuinely unknown at creation; the command carries `None`.
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
}

impl SeasonCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
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
        let result = SeasonAggregate::execute(&self.cmd_service, id, cmd)
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
}

/// Command adapter for the Block aggregate.
#[derive(Clone, Debug)]
pub struct BlockCommandsImpl {
    cmd_service: CommandService,
}

impl BlockCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
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
        let result = BlockAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
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
}

impl EpisodeCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
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
        let result = EpisodeAggregate::execute(&self.cmd_service, id, cmd)
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
}

impl SceneShootCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
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
        let result = SceneShootAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .metadata(EventMetadata {
                actor: Some(actor),
                provenance: Provenance::Human,
                series_id,
            })
            .await;
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
            entity: String::new(),
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
                .ok_or_else(|| DomainError::Conflict("command produced no events".into()))?;
            Ok((id, version))
        }
        Ok(ExecuteResult::Idempotent { current_version }) => {
            Ok((id, version_from_current(current_version)))
        }
        Ok(ExecuteResult::PendingTransaction { .. }) => Err(DomainError::Conflict(
            "pending transaction not supported".into(),
        )),
        Err(ExecuteError::Handle(err)) => Err(err.into()),
        Err(ExecuteError::IncorrectExpectedVersion {
            stream_id, current, ..
        }) => Err(DomainError::VersionConflict {
            entity: stream_id.to_string(),
            expected: AggregateVersion(0),
            current: version_from_current(current),
        }),
        Err(err) => Err(DomainError::Conflict(err.to_string())),
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
            entity: String::new(),
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
