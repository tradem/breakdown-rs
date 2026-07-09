## Why

The `api` crate's test structure is inconsistent with the conventions established in `core` and `infra`. All handler tests (~390 lines) live in a single separate file (`handlers/tests.rs`) with all Fake implementations bundled together. This makes tests hard to find and maintain, and violates the project's inline `#[cfg(test)]` pattern.

This refactoring aligns the `api` crate with the other crates' conventions and improves code organization before the test surface grows further (GitHub Issue #55).

## What Changes

- Split `handlers/tests.rs` into per-domain inline `#[cfg(test)]` modules (scene, character, costume, calculation)
- Extract shared test utilities (`FakePorts`, common imports) into a reusable test helper module
- Delete the standalone `handlers/tests.rs` file
- All existing tests pass unchanged — no behavioral changes

## Capabilities

### New Capabilities

_None — this is a pure code-organization refactoring._

### Modified Capabilities

_None — no requirement or spec-level behavior changes._

## Impact

- **Affected code**: `crates/api/src/handlers/` only
- **API impact**: None — test-only changes
- **Dependencies**: None
- **Systems**: CI (`cargo test -p api`) should continue to pass unchanged
