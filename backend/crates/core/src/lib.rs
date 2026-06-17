// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! # Core – Reine Domänenlogik
//!
//! Enthält **Commands**, **Events**, **Aggregates**, **Read-Model DTOs** und **Port Traits**.
//!
//! ## Architektur-Regeln
//! - Keine Abhängigkeiten zu `sqlx`, `axum` oder anderer Infrastruktur.
//! - Nur `serde`, `uuid`, `chrono`, `thiserror`, `kameo`, `kameo_es`.
//!
//! ## Ordner-Struktur (wird nach Bedarf erweitert)
//! - `command/`   – Command-Strukturen (z. B. `CreateScene`)
//! - `event/`     – Event-Enums (z. B. `SceneCreated`)
//! - `aggregate/` – Aggregat-Zustände (z. B. `SceneAggregate`)
//! - `dto/`       – Read-Model DTOs / Projections
//! - `port/`      – Port-Traits für außenliegende Adapter
//! - `error.rs`   – Zentrale Domain-Fehler

pub mod error;

/// Command-Module (wird später gefüllt)
pub mod command {
    // pub mod scene;
}

/// Event-Module
pub mod event {
    // pub mod scene;
}

/// Aggregat-Module
pub mod aggregate {
    // pub mod scene;
}

/// Read-Model DTOs
pub mod dto {
    // pub mod scene;
}

/// Port-Traits (Hexagonale Architektur)
pub mod port {
    // pub mod scene_repository;
}
