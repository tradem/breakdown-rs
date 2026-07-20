// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! AppState – Composition-Root (manuelles DI)
//!
//! `AppState` is generic over a `Ports` implementation so that unit tests can
//! substitute hand-written fakes without spinning up SierraDB or Postgres.

use breakdown_core::audit::AuditRepository;
use breakdown_core::block::{BlockCommands, BlockRepository};
use breakdown_core::character::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::{CostumeCommands, CostumeRepository};
use breakdown_core::episode::{EpisodeCommands, EpisodeRepository};
use breakdown_core::membership::{MembershipCommands, MembershipRepository};
use breakdown_core::scene::{SceneCommands, SceneRepository};
use breakdown_core::season::{SeasonCommands, SeasonRepository};
use infra::event_store::{
    BlockCommandsImpl, CharacterCommandsImpl, CostumeCommandsImpl, EpisodeCommandsImpl,
    MembershipCommandsImpl, SceneCommandsImpl, SeasonCommandsImpl,
};
use infra::queries::{
    AuditRepositoryImpl, BlockRepositoryImpl, CharacterRepositoryImpl, CostumeRepositoryImpl,
    EpisodeRepositoryImpl, MembershipRepositoryImpl, SceneRepositoryImpl, SeasonRepositoryImpl,
};

/// The hexagonal seam surface used by API handlers. Production implements it
/// with the concrete `kameo_es` write adapters and `sqlx` read adapters.
pub trait Ports: Clone + Send + Sync + 'static {
    type SceneCommands: SceneCommands;
    type SceneRepo: SceneRepository;
    type CharacterCommands: CharacterCommands;
    type CharacterRepo: CharacterRepository;
    type CostumeCommands: CostumeCommands;
    type CostumeRepo: CostumeRepository;
    type SeasonCommands: SeasonCommands;
    type SeasonRepo: SeasonRepository;
    type BlockCommands: BlockCommands;
    type BlockRepo: BlockRepository;
    type EpisodeCommands: EpisodeCommands;
    type EpisodeRepo: EpisodeRepository;
    type MembershipCommands: MembershipCommands;
    type MembershipRepo: MembershipRepository;
    type AuditRepo: AuditRepository;

    fn scene_commands(&self) -> &Self::SceneCommands;
    fn scene_repo(&self) -> &Self::SceneRepo;
    fn character_commands(&self) -> &Self::CharacterCommands;
    fn character_repo(&self) -> &Self::CharacterRepo;
    fn costume_commands(&self) -> &Self::CostumeCommands;
    fn costume_repo(&self) -> &Self::CostumeRepo;
    fn season_commands(&self) -> &Self::SeasonCommands;
    fn season_repo(&self) -> &Self::SeasonRepo;
    fn block_commands(&self) -> &Self::BlockCommands;
    fn block_repo(&self) -> &Self::BlockRepo;
    fn episode_commands(&self) -> &Self::EpisodeCommands;
    fn episode_repo(&self) -> &Self::EpisodeRepo;
    fn membership_commands(&self) -> &Self::MembershipCommands;
    fn membership_repo(&self) -> &Self::MembershipRepo;
    fn audit_repo(&self) -> &Self::AuditRepo;
}

/// Shared state handed to every Axum handler.
#[derive(Clone, Debug)]
pub struct AppState<P: Ports> {
    pub ports: P,
}

impl<P: Ports> AppState<P> {
    pub fn new(ports: P) -> Self {
        Self { ports }
    }
}

/// Production port bundle assembled in `main.rs`.
#[derive(Clone, Debug)]
pub struct ProductionPorts {
    scene_commands: SceneCommandsImpl,
    scene_repo: SceneRepositoryImpl,
    character_commands: CharacterCommandsImpl,
    character_repo: CharacterRepositoryImpl,
    costume_commands: CostumeCommandsImpl,
    costume_repo: CostumeRepositoryImpl,
    season_commands: SeasonCommandsImpl,
    season_repo: SeasonRepositoryImpl,
    block_commands: BlockCommandsImpl,
    block_repo: BlockRepositoryImpl,
    episode_commands: EpisodeCommandsImpl,
    episode_repo: EpisodeRepositoryImpl,
    membership_commands: MembershipCommandsImpl,
    membership_repo: MembershipRepositoryImpl,
    audit_repo: AuditRepositoryImpl,
}

impl ProductionPorts {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        scene_commands: SceneCommandsImpl,
        scene_repo: SceneRepositoryImpl,
        character_commands: CharacterCommandsImpl,
        character_repo: CharacterRepositoryImpl,
        costume_commands: CostumeCommandsImpl,
        costume_repo: CostumeRepositoryImpl,
        season_commands: SeasonCommandsImpl,
        season_repo: SeasonRepositoryImpl,
        block_commands: BlockCommandsImpl,
        block_repo: BlockRepositoryImpl,
        episode_commands: EpisodeCommandsImpl,
        episode_repo: EpisodeRepositoryImpl,
        membership_commands: MembershipCommandsImpl,
        membership_repo: MembershipRepositoryImpl,
        audit_repo: AuditRepositoryImpl,
    ) -> Self {
        Self {
            scene_commands,
            scene_repo,
            character_commands,
            character_repo,
            costume_commands,
            costume_repo,
            season_commands,
            season_repo,
            block_commands,
            block_repo,
            episode_commands,
            episode_repo,
            membership_commands,
            membership_repo,
            audit_repo,
        }
    }
}

impl Ports for ProductionPorts {
    type SceneCommands = SceneCommandsImpl;
    type SceneRepo = SceneRepositoryImpl;
    type CharacterCommands = CharacterCommandsImpl;
    type CharacterRepo = CharacterRepositoryImpl;
    type CostumeCommands = CostumeCommandsImpl;
    type CostumeRepo = CostumeRepositoryImpl;
    type SeasonCommands = SeasonCommandsImpl;
    type SeasonRepo = SeasonRepositoryImpl;
    type BlockCommands = BlockCommandsImpl;
    type BlockRepo = BlockRepositoryImpl;
    type EpisodeCommands = EpisodeCommandsImpl;
    type EpisodeRepo = EpisodeRepositoryImpl;
    type MembershipCommands = MembershipCommandsImpl;
    type MembershipRepo = MembershipRepositoryImpl;
    type AuditRepo = AuditRepositoryImpl;

    fn scene_commands(&self) -> &Self::SceneCommands {
        &self.scene_commands
    }
    fn scene_repo(&self) -> &Self::SceneRepo {
        &self.scene_repo
    }
    fn character_commands(&self) -> &Self::CharacterCommands {
        &self.character_commands
    }
    fn character_repo(&self) -> &Self::CharacterRepo {
        &self.character_repo
    }
    fn costume_commands(&self) -> &Self::CostumeCommands {
        &self.costume_commands
    }
    fn costume_repo(&self) -> &Self::CostumeRepo {
        &self.costume_repo
    }
    fn season_commands(&self) -> &Self::SeasonCommands {
        &self.season_commands
    }
    fn season_repo(&self) -> &Self::SeasonRepo {
        &self.season_repo
    }
    fn block_commands(&self) -> &Self::BlockCommands {
        &self.block_commands
    }
    fn block_repo(&self) -> &Self::BlockRepo {
        &self.block_repo
    }
    fn episode_commands(&self) -> &Self::EpisodeCommands {
        &self.episode_commands
    }
    fn episode_repo(&self) -> &Self::EpisodeRepo {
        &self.episode_repo
    }
    fn membership_commands(&self) -> &Self::MembershipCommands {
        &self.membership_commands
    }
    fn membership_repo(&self) -> &Self::MembershipRepo {
        &self.membership_repo
    }
    fn audit_repo(&self) -> &Self::AuditRepo {
        &self.audit_repo
    }
}
