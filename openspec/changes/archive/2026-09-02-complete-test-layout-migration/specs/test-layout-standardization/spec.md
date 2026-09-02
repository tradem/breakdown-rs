# Test Layout Standardization

## Purpose

Standardisierung aller Backend-Tests auf `tests/`-Verzeichnisse innerhalb ihrer Crates. Kein Test-Code mehr in Produktivcode (`src/`).

## ADDED Requirements

### Requirement: All tests in tests/ directories

All test functions MUST reside in the crate's `tests/` directory. Only `#[cfg(test)]` blocks that contain no test functions (e.g. `mod` declarations) and narrowly scoped test-only accessors behind `#[cfg(feature = "test-support")]` (e.g. `SceneRepositoryImpl::pool`) are allowed in `src/`.

#### Scenario: New test added to src/ directory

- **WHEN** ein Entwickler eine neue Testfunktion in einer Datei unter `src/` hinzufügt
- **THEN** schlägt `cargo test` fehl oder der Code-Review lehnt den PR ab

#### Scenario: Test in tests/ directory passes

- **WHEN** ein Test in `tests/` des jeweiligen Crates liegt
- **THEN** `cargo test -p <crate>` führt den Test erfolgreich aus

### Requirement: No path-based test modules

`#[path = "..."]` attributes for wiring up test modules MUST NOT be used. Test files SHALL be standalone files in `tests/`, never included via `#[path]` modules from `src/`.

#### Scenario: #[path] test module in source

- **WHEN** ein `#[cfg(test)] #[path = "..."] mod tests;` in einer `src/`-Datei existiert
- **THEN** wird dieser Block entfernt und die Tests nach `tests/` verschoben

### Requirement: Shared test helpers

Shared test helpers MUST be exported as `pub` from `test_support` or shared via a crate's `tests/common/mod.rs`. Helpers MUST NOT be duplicated across test files.

#### Scenario: Multiple test files need same helper

- **WHEN** mehrere Testdateien in einem Crate denselben Helfer benötigen
- **THEN** wird der Helfer in `tests/common/mod.rs` oder `test_support` definiert

### Requirement: Visibility adjustments

Items required by external tests MUST be lifted from `pub(crate)` to `pub` using the minimal visibility that satisfies the test. The change MUST use the least visible level that compiles.

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
| `src/queries/scene_test.rs` | *gelöscht* | Entfernung |

> Hinweis: `scene_test.rs` enthielt keine Testfunktionen, sondern nur den
test-only `pool()`-Accessor. Der Accessor wurde in `scene.rs` hinter das
`test-support`-Feature verschoben; die Datei selbst wurde entfernt.
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
