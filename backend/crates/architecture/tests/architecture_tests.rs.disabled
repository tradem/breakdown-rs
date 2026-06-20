// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use arch_test::Architecture;

#[test]
fn test_domain_isolation_rules() {
    // 1. Definiert die Architektur-Struktur eures Workspace
    let architecture = Architecture::new();

    // 2. Regel: Das Domain-Modell (core) darf NIEMALS Infrastruktur-Details kennen
    // Es darf keine Module importieren, die "database", "sqlx" oder "http" im Namen tragen.
    architecture
        .layer("core")
        .should_not_depend_on("infra")
        .should_not_depend_on("api");

    // 3. Regel: Euer Event-Sourcing-Kern (in core::domain) darf nicht von
    // äußeren Applikations-Services (core::application) importiert werden (Abhängigkeiten zeigen nach innen)
    architecture
        .layer("core::domain")
        .should_not_depend_on("core::application");

    // 4. Test ausführen und validieren
    architecture.assert_all_rules();
}
