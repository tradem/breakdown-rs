## Why

Issue #127 standardisiert die Test-Layouts auf `tests/`-Verzeichnisse. Die bisherige Migration (PR #133) hat das `reporting`-Modul und weitere Bereiche übersehen. Produktivcode enthält noch Test-Module über `#[cfg(test)] mod tests;`, `#[path]`-Einbindungen und inline `#[cfg(test)]`-Blöcke — gegen die definierten Regeln.

## What Changes

- **Core crate**: 12 `aggregate_test.rs`-Schwestermodule → `tests/`, 3 reporting-inline-Tests → `tests/`, 1 proptest → `tests/`
- **Infra crate**: 2 `#[path]`-Testdateien in `event_store/` → `tests/`, 1 Supervisor-Test → `tests/`, 1 Scene-Query-Test → `tests/`, 1 Storage-Contract-Test → `tests/`, 7 reporting-inline-Tests → `tests/`, 1 Saga-Inline-Test → `tests/`
- **Api crate**: 7 handler `#[path]`-Testdateien → `tests/`, 3 auth `#[path]`-Testdateien → `tests/`, `test_helpers.rs` → `tests/common/mod.rs`
- **Sichtbarkeit**: `pub(crate)`-Helfer die von Tests benötigt werden, werden auf `pub` gehob oder nach `test_support` verschoben
- **Kein Test-Code mehr in `src/`**: Alle `#[cfg(test)]`-Blöcke mit Testfunktionen werden entfernt

## Capabilities

### New Capabilities

- `test-layout-standardization`: Vollständige Migration aller verbleibenden Inline- und Schwestermodule-Tests in `tests/`-Verzeichnisse aller Backend-Crates

### Modified Capabilities

- `architecture-testing`: Aktualisierung der Test-Layout-Regeln in der CI/Architektur-Dokumentation

## Impact

- **Code**: ~40+ Testdateien werden verschoben/umstrukturiert
- **CI**: `cargo test` muss weiterhin alle Tests finden (Integration-Tests in `tests/` sind extern)
- **Sichtbarkeit**: Einige `pub(crate)`-Funktionen müssen auf `pub` gehoben werden
- **Abhängigkeiten**: `test_support`-Crate wird erweitert für gemeinsame Test-Helfer
