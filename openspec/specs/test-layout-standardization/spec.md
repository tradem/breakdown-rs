# test-layout-standardization Specification

## Purpose
TBD - created by archiving change complete-test-layout-migration. Update Purpose after archive.
## Requirements
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

