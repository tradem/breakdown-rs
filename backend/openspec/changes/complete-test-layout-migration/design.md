# Design: Complete Test Layout Migration

## Überblick

Migration aller verbleibenden Inline-Tests und `#[path]`-Module in `tests/`-Verzeichnisse gemäß Issue #127 Variante B.

## Architektur-Entscheidungen

### 1. Test-Import-Pattern

**Aktuell (in src/):**
```rust
#[cfg(test)]
mod tests {
    use super::*;
    // Tests verwenden Items aus dem Parent-Modul
}
```

**Ziel (in tests/):**
```rust
use breakdown_core::block::*;
use test_support::make_ctx;
// Tests verwenden pub-Items aus dem Crate
```

### 2. Sichtbarkeits-Änderungen

Tests in `tests/` (extern) können nur `pub`-Items verwenden. Folgende Strategie:

- **Aggregate-State-Structs**: Bereits `pub` ✓
- **Commands/Events**: Bereits `pub` ✓  
- **`pub(crate)`-Helfer**: Auf `pub` heben oder nach `test_support` verschieben
- **Test-spezifische Helper**: In `tests/common/mod.rs` des jeweiligen Crates

### 3. Datei-Mapping

#### Core Crate

| Aktuell | Ziel |
|---------|------|
| `src/block/aggregate_test.rs` | `tests/block_aggregate.rs` |
| `src/character/aggregate_test.rs` | `tests/character_aggregate.rs` |
| `src/costume/aggregate_test.rs` | `tests/costume_aggregate.rs` |
| `src/costume_category/aggregate_test.rs` | `tests/costume_category_aggregate.rs` |
| `src/episode/aggregate_test.rs` | `tests/episode_aggregate.rs` |
| `src/membership/aggregate_test.rs` | `tests/membership_aggregate.rs` |
| `src/photo/aggregate_test.rs` | `tests/photo_aggregate.rs` |
| `src/scene/aggregate_test.rs` | `tests/scene_aggregate.rs` |
| `src/scene_shoot/aggregate_test.rs` | `tests/scene_shoot_aggregate.rs` |
| `src/season/aggregate_test.rs` | `tests/season_aggregate.rs` |
| `src/shooting_day/aggregate_test.rs` | `tests/shooting_day_aggregate.rs` |
| `src/shared_test.rs` | `tests/shared.rs` |
| `src/proptest.rs` | `tests/proptest.rs` |
| `src/reporting/mod.rs` inline | `tests/reporting_mod.rs` |
| `src/reporting/storage.rs` inline | `tests/reporting_storage.rs` |
| `src/reporting/archival.rs` inline | `tests/reporting_archival.rs` |

#### Infra Crate

| Aktuell | Ziel |
|---------|------|
| `src/event_store/adapter_mapping_tests.rs` | `tests/adapter_mapping.rs` |
| `src/event_store/translation_tests.rs` | `tests/translation.rs` |
| `src/projectors/supervisor_test.rs` | `tests/supervisor.rs` |
| `src/queries/scene_test.rs` | `tests/scene_query.rs` |
| `src/reporting/storage_contract_test.rs` | `tests/reporting_storage_contract.rs` |
| `src/reporting/backup.rs` inline | `tests/reporting_backup.rs` |
| `src/reporting/jobs.rs` inline | `tests/reporting_jobs.rs` |
| `src/reporting/locale.rs` inline | `tests/reporting_locale.rs` |
| `src/reporting/mod.rs` inline | `tests/reporting_mod.rs` |
| `src/reporting/storage.rs` inline | `tests/reporting_storage.rs` |
| `src/reporting/triggers.rs` inline | `tests/reporting_triggers.rs` |
| `src/reporting/typst_renderer.rs` inline | `tests/reporting_typst_renderer.rs` |
| `src/sagas/season_seeding.rs` inline | `tests/season_seeding.rs` |

#### Api Crate

| Aktuell | Ziel |
|---------|------|
| `src/handlers/scene_tests.rs` | `tests/handler_scene.rs` |
| `src/handlers/character_tests.rs` | `tests/handler_character.rs` |
| `src/handlers/costume_tests.rs` | `tests/handler_costume.rs` |
| `src/handlers/authz_tests.rs` | `tests/handler_authz.rs` |
| `src/handlers/audit_tests.rs` | `tests/handler_audit.rs` |
| `src/handlers/membership_tests.rs` | `tests/handler_membership.rs` |
| `src/handlers/report_tests.rs` | `tests/handler_report.rs` |
| `src/handlers/test_helpers.rs` | `tests/common/mod.rs` |
| `src/auth/authorization_test.rs` | `tests/auth_authorization.rs` |
| `src/auth/jwks_test.rs` | `tests/auth_jwks.rs` |
| `src/auth/mod_test.rs` | `tests/auth_mod.rs` |

### 4. Migration-Strategie pro Crate

1. **Core zuerst** (keine externen Abhängigkeiten)
2. **Infra danach** (hängt von core ab)
3. **Api zuletzt** (hängt von core + infra ab)

Jeder Crate wird als separater Commit migrriert, um `cargo test` zwischen den Schritten laufen zu lassen.

### 5. `#[cfg(test)]`-Blöcke in src/

Verbleibende `#[cfg(test)]`-Blöcke in `src/` sind nur akzeptabel wenn:
- Sie KEINE Testfunktionen enthalten (nur `mod`-Deklarationen)
- Sie auf `pub(crate)`-Items zugreifen müssen

Alle `#[cfg(test)] mod tests;`-Deklarationen werden entfernt.
Alle inline `#[cfg(test)] mod tests { ... }`-Blöcke mit `#[test]`-Funktionen werden entfernt.

### 6. `test_support`-Ergänzungen

Das `test_support`-Crate wird um gemeinsame Test-Helfer ergänzt die von mehreren Crates genutzt werden.

## Risiken

- **Sichtbarkeit**: `pub(crate)`-Items die von Tests genutzt werden müssen auf `pub` gehoben werden — erhöht die öffentliche API
- **Import-Pfade**: Externe Tests brauchen explizite Importe statt `use super::*`
- **Feature-Gates**: Tests die hinter `#[cfg(test)]` feature-abhängig sind, müssen ggf. angepasst werden
