# Test Layout Standardization

## Purpose

Standardisierung aller Backend-Tests auf `tests/`-Verzeichnisse innerhalb ihrer Crates. Kein Test-Code mehr in Produktivcode (`src/`).

## Requirements

### Requirement: All tests in tests/ directories

Alle Testfunktionen MÜSSEN in `tests/`-Verzeichnissen des jeweiligen Crates liegen. Ausnahmen sind nur `#[cfg(test)]`-Blöcke die KEINE Testfunktionen enthalten (z.B. `mod`-Deklarationen).

#### Scenario: New test added to src/ directory

- **WHEN** ein Entwickler eine neue Testfunktion in einer Datei unter `src/` hinzufügt
- **THEN** schlägt `cargo test` fehl oder der Code-Review lehnt den PR ab

#### Scenario: Test in tests/ directory passes

- **WHEN** ein Test in `tests/` des jeweiligen Crates liegt
- **THEN** `cargo test -p <crate>` führt den Test erfolgreich aus

### Requirement: No path-based test modules

`#[path = "..."]`-Attribute zum Einbinden von Testdateien sind ABGESCHAFFT. Testdateien werden nicht über `#[path]` sondern als separate Dateien in `tests/` eingebunden.

#### Scenario: #[path] test module in source

- **WHEN** ein `#[cfg(test)] #[path = "..."] mod tests;` in einer `src/`-Datei existiert
- **THEN** wird dieser Block entfernt und die Tests nach `tests/` verschoben

### Requirement: Shared test helpers

Gemeinsame Test-Helfer werden als `pub` aus `test_support` exportiert oder in `tests/common/mod.rs` des jeweiligen Crates geteilt. Keine Duplikierung.

#### Scenario: Multiple test files need same helper

- **WHEN** mehrere Testdateien in einem Crate denselben Helfer benötigen
- **THEN** wird der Helfer in `tests/common/mod.rs` oder `test_support` definiert

### Requirement: Visibility adjustments

`pub(crate)`-Items die von externen Tests (`tests/`) benötigt werden, MÜSSEN auf `pub` gehoben werden. Die Änderung muss minimale Sichtbarkeit verwenden.

#### Scenario: Test needs pub(crate) function

- **WHEN** ein Test in `tests/` eine `pub(crate)`-Funktion aufruft
- **THEN** wird die Funktion auf `pub` gehob (mit doc-comment falls nötig)

## File Mapping

### Core Crate

| Quelle | Ziel | Typ |
|--------|------|-----|
| `src/block/aggregate_test.rs` | `tests/block_aggregate.rs` | Verschiebung |
| `src/character/aggregate_test.rs` | `tests/character_aggregate.rs` | Verschiebung |
| `src/costume/aggregate_test.rs` | `tests/costume_aggregate.rs` | Verschiebung |
| `src/costume_category/aggregate_test.rs` | `tests/costume_category_aggregate.rs` | Verschiebung |
| `src/episode/aggregate_test.rs` | `tests/episode_aggregate.rs` | Verschiebung |
| `src/membership/aggregate_test.rs` | `tests/membership_aggregate.rs` | Verschiebung |
| `src/photo/aggregate_test.rs` | `tests/photo_aggregate.rs` | Verschiebung |
| `src/scene/aggregate_test.rs` | `tests/scene_aggregate.rs` | Verschiebung |
| `src/scene_shoot/aggregate_test.rs` | `tests/scene_shoot_aggregate.rs` | Verschiebung |
| `src/season/aggregate_test.rs` | `tests/season_aggregate.rs` | Verschiebung |
| `src/shooting_day/aggregate_test.rs` | `tests/shooting_day_aggregate.rs` | Verschiebung |
| `src/shared_test.rs` | `tests/shared.rs` | Verschiebung |
| `src/proptest.rs` | `tests/proptest.rs` | Verschiebung |
| `src/reporting/mod.rs` inline | `tests/reporting_mod.rs` | Extraktion |
| `src/reporting/storage.rs` inline | `tests/reporting_storage.rs` | Extraktion |
| `src/reporting/archival.rs` inline | `tests/reporting_archival.rs` | Extraktion |

### Infra Crate

| Quelle | Ziel | Typ |
|--------|------|-----|
| `src/event_store/adapter_mapping_tests.rs` | `tests/adapter_mapping.rs` | Verschiebung |
| `src/event_store/translation_tests.rs` | `tests/translation.rs` | Verschiebung |
| `src/projectors/supervisor_test.rs` | `tests/supervisor.rs` | Verschiebung |
| `src/queries/scene_test.rs` | `tests/scene_query.rs` | Verschiebung |
| `src/reporting/storage_contract_test.rs` | `tests/reporting_storage_contract.rs` | Verschiebung |
| `src/reporting/backup.rs` inline | `tests/reporting_backup.rs` | Extraktion |
| `src/reporting/jobs.rs` inline | `tests/reporting_jobs.rs` | Extraktion |
| `src/reporting/locale.rs` inline | `tests/reporting_locale.rs` | Extraktion |
| `src/reporting/mod.rs` inline | `tests/reporting_mod.rs` | Extraktion |
| `src/reporting/storage.rs` inline | `tests/reporting_storage.rs` | Extraktion |
| `src/reporting/triggers.rs` inline | `tests/reporting_triggers.rs` | Extraktion |
| `src/reporting/typst_renderer.rs` inline | `tests/reporting_typst_renderer.rs` | Extraktion |
| `src/sagas/season_seeding.rs` inline | `tests/season_seeding.rs` | Extraktion |

### Api Crate

| Quelle | Ziel | Typ |
|--------|------|-----|
| `src/handlers/scene_tests.rs` | `tests/handler_scene.rs` | Verschiebung |
| `src/handlers/character_tests.rs` | `tests/handler_character.rs` | Verschiebung |
| `src/handlers/costume_tests.rs` | `tests/handler_costume.rs` | Verschiebung |
| `src/handlers/authz_tests.rs` | `tests/handler_authz.rs` | Verschiebung |
| `src/handlers/audit_tests.rs` | `tests/handler_audit.rs` | Verschiebung |
| `src/handlers/membership_tests.rs` | `tests/handler_membership.rs` | Verschiebung |
| `src/handlers/report_tests.rs` | `tests/handler_report.rs` | Verschiebung |
| `src/handlers/test_helpers.rs` | `tests/common/mod.rs` | Verschiebung |
| `src/auth/authorization_test.rs` | `tests/auth_authorization.rs` | Verschiebung |
| `src/auth/jwks_test.rs` | `tests/auth_jwks.rs` | Verschiebung |
| `src/auth/mod_test.rs` | `tests/auth_mod.rs` | Verschiebung |
