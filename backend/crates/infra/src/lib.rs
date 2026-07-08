// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! # Infra – Infrastruktur-Implementierungen
//!
//! Enthält:
//! - **EventStore**-Integration (Postgres via `kameo_es`)
//! - **Projectors** (Read-Model-Updater)
//! - **sqlx**-Queries für Projection-Tabellen
//!
//! ## Architektur-Regeln
//! - Implementiert die Port-Traits aus `core`.
//! - Darf `sqlx`, `axum` etc. verwenden.
//!
//! ## Ordner-Struktur
//! - `event_store/` – EventStore-Adapter
//! - `projectors/`  – Event-Handler / Projectoren
//! - `queries/`     – sqlx-Read-Queries

pub mod event_store;
pub mod projectors;
pub mod queries;
