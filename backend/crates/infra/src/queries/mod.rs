// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! sqlx-Read-Queries für Projection-Tabellen

mod block;
mod character;
mod costume;
mod episode;
mod audit;
mod membership;
mod scene;
mod season;

pub use block::BlockRepositoryImpl;
pub use character::CharacterRepositoryImpl;
pub use costume::CostumeRepositoryImpl;
pub use episode::EpisodeRepositoryImpl;
pub use audit::AuditRepositoryImpl;
pub use membership::MembershipRepositoryImpl;
pub use scene::SceneRepositoryImpl;
pub use season::SeasonRepositoryImpl;
