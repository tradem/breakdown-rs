# Tasks: Complete Test Layout Migration

## Core Crate

### Phase 1: Aggregate-Tests verschieben

- [x] `crates/core/src/block/aggregate_test.rs` → `tests/block_aggregate.rs`
  - `use super::*;` → `use breakdown_core::block::*;`
  - `#[cfg(test)] mod tests;` in `aggregate.rs` entfernen
  - `cargo test -p breakdown_core --test block_aggregate` prüfen

- [x] `crates/core/src/character/aggregate_test.rs` → `tests/character_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/costume/aggregate_test.rs` → `tests/costume_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/costume_category/aggregate_test.rs` → `tests/costume_category_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/episode/aggregate_test.rs` → `tests/episode_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/membership/aggregate_test.rs` → `tests/membership_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/photo/aggregate_test.rs` → `tests/photo_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/scene/aggregate_test.rs` → `tests/scene_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/scene_shoot/aggregate_test.rs` → `tests/scene_shoot_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/season/aggregate_test.rs` → `tests/season_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/shooting_day/aggregate_test.rs` → `tests/shooting_day_aggregate.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` entfernen

- [x] `crates/core/src/shared_test.rs` → `tests/shared.rs`
  - Importe anpassen
  - `#[cfg(test)] mod tests;` in `shared.rs` entfernen

- [x] `crates/core/src/proptest.rs` → `tests/proptest.rs`
  - `mod proptest;` in `lib.rs` entfernen

### Phase 2: Reporting-Tests extrahieren

- [x] `crates/core/src/reporting/mod.rs` inline Tests → `tests/reporting_mod.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen nach `tests/reporting_mod.rs` extrahieren
  - Importe: `use breakdown_core::reporting::*;`

- [x] `crates/core/src/reporting/storage.rs` inline Tests → `tests/reporting_storage.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/core/src/reporting/archival.rs` inline Tests → `tests/reporting_archival.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

### Phase 3: Sichtbarkeit anpassen

- [x] Prüfe ob alle genutzten Items `pub` sind
  - Führe `cargo test -p breakdown_core` aus
  - Bei Sichtbarkeitsfehlern: Items auf `pub` heben

---

## Infra Crate

### Phase 4: Bestehende Testdateien verschieben

- [x] `crates/infra/src/event_store/adapter_mapping_tests.rs` → `tests/adapter_mapping.rs`
  - `#[path]` in `command_adapters.rs` entfernen
  - Importe anpassen

- [x] `crates/infra/src/event_store/translation_tests.rs` → `tests/translation.rs`
  - `#[path]` in `command_adapters.rs` entfernen
  - Importe anpassen

- [x] `crates/infra/src/projectors/supervisor_test.rs` → `tests/supervisor.rs`
  - `#[path]` in `supervisor.rs` entfernen
  - Importe anpassen

- [x] `crates/infra/src/queries/scene_test.rs` → `tests/scene_query.rs`
  - `#[path]` in `scene.rs` entfernen
  - Importe anpassen

- [x] `crates/infra/src/reporting/storage_contract_test.rs` → `tests/reporting_storage_contract.rs`
  - `#[path]` in `storage.rs` entfernen
  - Importe anpassen

### Phase 5: Reporting-Inline-Tests extrahieren

- [x] `crates/infra/src/reporting/backup.rs` inline Tests → `tests/reporting_backup.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/infra/src/reporting/jobs.rs` inline Tests → `tests/reporting_jobs.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/infra/src/reporting/locale.rs` inline Tests → `tests/reporting_locale.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/infra/src/reporting/mod.rs` inline Tests → `tests/reporting_mod.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/infra/src/reporting/storage.rs` inline Tests → `tests/reporting_storage.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/infra/src/reporting/triggers.rs` inline Tests → `tests/reporting_triggers.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

- [x] `crates/infra/src/reporting/typst_renderer.rs` inline Tests → `tests/reporting_typst_renderer.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

### Phase 6: Saga-Inline-Tests extrahieren

- [x] `crates/infra/src/sagas/season_seeding.rs` inline Tests → `tests/season_seeding.rs`
  - `#[cfg(test)] mod tests { ... }` Block entfernen
  - Testfunktionen extrahieren

### Phase 7: Sichtbarkeit anpassen

- [x] Prüfe ob alle genutzten Items `pub` sind
  - Führe `cargo test -p breakdown_infra` aus
  - Bei Sichtbarkeitsfehlern: Items auf `pub` heben

---

## Api Crate

### Phase 8: Handler-Tests verschieben

- [x] `crates/api/src/handlers/test_helpers.rs` → `tests/common/mod.rs`
  - `#[path]` in `mod.rs` entfernen
  - Test-Helfer als `pub` exportieren

- [x] `crates/api/src/handlers/scene_tests.rs` → `tests/handler_scene.rs`
  - `#[path]` in `mod.rs` entfernen
  - Importe: `use super::common::*;` → `use crate::common::*;` (overhead)

- [x] `crates/api/src/handlers/character_tests.rs` → `tests/handler_character.rs`
  - `#[path]` entfernen
  - Importe anpassen

- [x] `crates/api/src/handlers/costume_tests.rs` → `tests/handler_costume.rs`
  - `#[path]` entfernen
  - Importe anpassen

- [x] `crates/api/src/handlers/authz_tests.rs` → `tests/handler_authz.rs`
  - `#[path]` entfernen
  - Importe anpassen

- [x] `crates/api/src/handlers/audit_tests.rs` → `tests/handler_audit.rs`
  - `#[path]` entfernen
  - Importe anpassen

- [x] `crates/api/src/handlers/membership_tests.rs` → `tests/handler_membership.rs`
  - `#[path]` entfernen
  - Importe anpassen

- [x] `crates/api/src/handlers/report_tests.rs` → `tests/handler_report.rs`
  - `#[path]` entfernen
  - Importe anpassen

### Phase 9: Auth-Tests verschieben

- [x] `crates/api/src/auth/authorization_test.rs` → `tests/auth_authorization.rs`
  - `#[path]` in `authorization.rs` entfernen
  - Importe anpassen

- [x] `crates/api/src/auth/jwks_test.rs` → `tests/auth_jwks.rs`
  - `#[path]` in `jwks.rs` entfernen
  - Importe anpassen

- [x] `crates/api/src/auth/mod_test.rs` → `tests/auth_mod.rs`
  - `#[path]` in `mod.rs` entfernen
  - Importe anpassen

### Phase 10: Sichtbarkeit anpassen

- [x] Prüfe ob alle genutzten Items `pub` sind
  - Führe `cargo test -p api` aus
  - Bei Sichtbarkeitsfehlern: Items auf `pub` heben

---

## Abschluss

### Phase 11: Vollständiger Test-Durchlauf

- [x] `cargo test --workspace` ausführen
  - Alle Tests müssen grün sein
  - Keine `#[cfg(test)]`-Blöcke mit Testfunktionen in `src/` mehr

### Phase 12: Architecture-Tests aktualisieren

- [x] Architektur-Test auf `#[path]`-Verbote erweitern
  - Sicherstellen dass keine neuen `#[path]`-Testmodule entstehen

### Phase 13: Dokumentation aktualisieren

- [x] Issue #127 Status aktualisieren
- [x] AGENTS.md Test-Regeln prüfen
