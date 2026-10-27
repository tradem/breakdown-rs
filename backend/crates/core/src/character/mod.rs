// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Character domain.

pub mod aggregate;
pub mod category;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::CharacterAggregate;
pub use category::CharacterCategory;
pub use commands::{
    CreateCharacter, UpdateCharacterCategory, UpdateContactInfo, UpdateMeasurements,
};
pub use error::CharacterError;
pub use events::{CharacterEvent, CharacterMeasurements, ContactInfo};
pub use ports::{CharacterCommands, CharacterRepository};
pub use views::{AppearanceOutfitView, CharacterAppearanceView, CharacterView};
