//! # Api – Axum Web-Server
//!
//! Übersetzt HTTP-Requests in:
//! - **Write:** Core-Commands → Aggregate → Events
//! - **Read:** Infra-Queries → Projection-Daten
//!
//! ## Ordner-Struktur
//! - `handlers/`  – Axum-Handler-Funktionen
//! - `routes/`    – Router-Definitionen
//! - `state.rs`   – AppState (Actor-Refs, Connection-Pool)
//! - `main.rs`    – Composition-Root (manuelles DI)

pub mod handlers;
pub mod routes;
pub mod state;
