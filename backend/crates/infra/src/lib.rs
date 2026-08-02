// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used, clippy::panic))]
#![cfg_attr(
    test,
    allow(clippy::print_stdout, clippy::print_stderr, clippy::dbg_macro)
)]
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
pub mod photo;
pub mod projectors;
pub mod queries;
pub mod reporting;
pub mod sagas;
pub mod tls;
pub mod vault;
