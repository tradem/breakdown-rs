// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

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
pub use commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
pub use error::CharacterError;
pub use events::{CharacterEvent, CharacterMeasurements, ContactInfo};
pub use ports::{CharacterCommands, CharacterRepository};
pub use views::CharacterView;
