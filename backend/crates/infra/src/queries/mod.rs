// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! sqlx-Read-Queries für Projection-Tabellen

mod audit;
mod block;
mod character;
mod costume;
mod costume_category;
mod episode;
mod membership;
mod scene;
mod season;
mod shooting_day;

pub use audit::AuditRepositoryImpl;
pub use block::BlockRepositoryImpl;
pub use character::CharacterRepositoryImpl;
pub use costume::CostumeRepositoryImpl;
pub use costume_category::CostumeCategoryRepositoryImpl;
pub use episode::EpisodeRepositoryImpl;
pub use membership::MembershipRepositoryImpl;
pub use scene::SceneRepositoryImpl;
pub use season::SeasonRepositoryImpl;
pub use shooting_day::ShootingDayRepositoryImpl;
