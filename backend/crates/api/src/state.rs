// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! AppState – Composition-Root (manuelles DI)
//!
//! `AppState` is generic over a `Ports` implementation so that unit tests can
//! substitute hand-written fakes without spinning up SierraDB or Postgres.

use breakdown_core::calculation::{CalculationCommands, CalculationRepository};
use breakdown_core::character::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::{CostumeCommands, CostumeRepository};
use breakdown_core::scene::{SceneCommands, SceneRepository};
use infra::event_store::{
    CalculationCommandsImpl, CharacterCommandsImpl, CostumeCommandsImpl, SceneCommandsImpl,
};
use infra::queries::{
    CalculationRepositoryImpl, CharacterRepositoryImpl, CostumeRepositoryImpl, SceneRepositoryImpl,
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
    type CalculationCommands: CalculationCommands;
    type CalculationRepo: CalculationRepository;

    fn scene_commands(&self) -> &Self::SceneCommands;
    fn scene_repo(&self) -> &Self::SceneRepo;
    fn character_commands(&self) -> &Self::CharacterCommands;
    fn character_repo(&self) -> &Self::CharacterRepo;
    fn costume_commands(&self) -> &Self::CostumeCommands;
    fn costume_repo(&self) -> &Self::CostumeRepo;
    fn calculation_commands(&self) -> &Self::CalculationCommands;
    fn calculation_repo(&self) -> &Self::CalculationRepo;
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
    calculation_commands: CalculationCommandsImpl,
    calculation_repo: CalculationRepositoryImpl,
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
        calculation_commands: CalculationCommandsImpl,
        calculation_repo: CalculationRepositoryImpl,
    ) -> Self {
        Self {
            scene_commands,
            scene_repo,
            character_commands,
            character_repo,
            costume_commands,
            costume_repo,
            calculation_commands,
            calculation_repo,
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
    type CalculationCommands = CalculationCommandsImpl;
    type CalculationRepo = CalculationRepositoryImpl;

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
    fn calculation_commands(&self) -> &Self::CalculationCommands {
        &self.calculation_commands
    }
    fn calculation_repo(&self) -> &Self::CalculationRepo {
        &self.calculation_repo
    }
}
