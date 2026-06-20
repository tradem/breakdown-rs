// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Calculation domain.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;

pub use events::{CalculationHeader, CalculationItem};
