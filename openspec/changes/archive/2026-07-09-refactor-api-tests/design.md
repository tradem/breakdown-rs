## Context

The `api` crate currently stores all handler tests in a single file `handlers/tests.rs` (~390 lines). This file contains:
- 8 Fake implementations (`FakeSceneCommands`, `FakeSceneRepo`, `FakeCharacterCommands`, `FakeCharacterRepo`, `FakeCostumeCommands`, `FakeCostumeRepo`, `FakeCalculationCommands`, `FakeCalculationRepo`)
- A `FakePorts` struct aggregating all fakes
- Tests for scene, character, costume, and calculation handlers

In contrast, `core` and `infra` use inline `#[cfg(test)]` modules at the bottom of each file, with test helpers scoped to their module.

The `handlers/mod.rs` file currently has a `#[cfg(test)]` block that references the external `tests` module.

## Goals / Non-Goals

**Goals:**
- Align `api` test structure with `core`/`infra` conventions (inline `#[cfg(test)]`)
- Co-locate handler tests with the code they test
- Extract shared test utilities for reuse across test modules
- Maintain identical test coverage and behavior

**Non-Goals:**
- Changing handler logic or API behavior
- Adding new tests (only restructuring existing ones)
- Modifying `core` or `infra` crates

## Decisions

### Decision 1: Split tests into per-domain modules within `handlers/mod.rs`

**Choice**: Keep tests in `handlers/mod.rs` as inline `#[cfg(test)]` modules, one per domain (scene, character, costume, calculation).

**Rationale**: The handlers are all in a single `mod.rs` file. Splitting into separate handler files (e.g., `handlers/scene.rs`) would be a larger refactoring beyond scope. Inline modules match the `core`/`infra` pattern.

**Alternative considered**: Separate `handlers/tests/scene.rs`, `handlers/tests/character.rs`, etc. — rejected as overly nested for the current code size.

### Decision 2: Extract shared test utilities into `handlers/test_helpers`

**Choice**: Create a `#[cfg(test)] pub(crate) mod test_helpers` in `handlers/mod.rs` containing:
- `FakePorts` struct and its `Ports` implementation
- All 8 Fake implementations
- Common test imports

**Rationale**: Multiple test modules need `FakePorts` and the individual fakes. Extracting them avoids duplication. The `pub(crate)` visibility allows use from any test module within the crate.

**Alternative considered**: Duplicate fakes per test module — rejected as it increases maintenance burden.

### Decision 3: Keep `FakePorts` generic over domain

**Choice**: `FakePorts` remains a single struct implementing `Ports` with all domain fakes, rather than creating per-domain port bundles.

**Rationale**: The `Ports` trait bundles all domains together. Splitting would require trait changes beyond scope.

## Risks / Trade-offs

- **[Risk] Test discovery changes** → Mitigation: Run `cargo test -p api` before and after; compare test count and names.
- **[Risk] Import path changes break compilation** → Mitigation: Compiler errors will surface immediately; fix in-place.
- **[Trade-off] Longer `mod.rs` file** → Acceptable: Test code is `#[cfg(test)]` gated and doesn't affect production binary size.
