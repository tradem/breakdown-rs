// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! # Breakdown RS – API-Server
//!
//! Composition-Root: Hier werden alle Abhängigkeiten per Hand injiziert
//! (Poor Man's Dependency Injection gemäß hexagonaler Architektur).

use api::state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Logging initialisieren
    tracing_subscriber::fmt::init();

    // TODO: Config laden (Umgebungsvariablen / dotenv)
    // TODO: Datenbank-Pool erstellen
    // TODO: EventStore initialisieren
    // TODO: Aggregate spawnen (kameo-Actors)
    // TODO: Projector-Subscriptions starten
    // TODO: Router bauen und Server starten

    let _app_state = AppState {};
    tracing::info!("🚀 Breakdown RS starting...");

    Ok(())
}
