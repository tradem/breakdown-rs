## 1. Prepare test infrastructure

## 1. Prepare test infrastructure

- [x] 1.1 Create `test_helpers` module in `handlers/mod.rs` with `#[cfg(test)] pub(crate) mod test_helpers { ... }`
- [x] 1.2 Move all 8 Fake implementations (`FakeSceneCommands`, `FakeSceneRepo`, `FakeCharacterCommands`, `FakeCharacterRepo`, `FakeCostumeCommands`, `FakeCostumeRepo`, `FakeCalculationCommands`, `FakeCalculationRepo`) into `test_helpers`
- [x] 1.3 Move `FakePorts` struct and its `Ports` implementation into `test_helpers`
- [x] 1.4 Verify `cargo test -p api` still compiles (tests may fail due to moved items)

## 2. Migrate scene handler tests

- [x] 2.1 Create `#[cfg(test)] mod scene_tests { ... }` in `handlers/mod.rs`
- [x] 2.2 Move scene handler test functions from `tests.rs` into `scene_tests`
- [x] 2.3 Update imports to use `super::test_helpers::*`
- [x] 2.4 Verify scene tests pass with `cargo test -p api scene`

## 3. Migrate character handler tests

- [x] 3.1 Create `#[cfg(test)] mod character_tests { ... }` in `handlers/mod.rs`
- [x] 3.2 No character handler tests exist in the original `tests.rs` — only scene tests were present. Module created, ready for future tests.
- [x] 3.3 Module created with appropriate structure; no imports needed yet.
- [x] 3.4 Verified `cargo test -p api` compiles with module present.

## 4. Migrate costume handler tests

- [x] 4.1 Create `#[cfg(test)] mod costume_tests { ... }` in `handlers/mod.rs`
- [x] 4.2 No costume handler tests exist in the original `tests.rs` — only scene tests were present. Module created, ready for future tests.
- [x] 4.3 Module created with appropriate structure; no imports needed yet.
- [x] 4.4 Verified `cargo test -p api` compiles with module present.

## 5. Migrate calculation handler tests

- [x] 5.1 Create `#[cfg(test)] mod calculation_tests { ... }` in `handlers/mod.rs`
- [x] 5.2 No calculation handler tests exist in the original `tests.rs` — only scene tests were present. Module created, ready for future tests.
- [x] 5.3 Module created with appropriate structure; no imports needed yet.
- [x] 5.4 Verified `cargo test -p api` compiles with module present.

## 6. Cleanup and verification

- [x] 6.1 Delete `handlers/tests.rs`
- [x] 6.2 Remove `mod tests;` declaration from `handlers/mod.rs` (replaced with inline modules)
- [x] 6.3 Run full `cargo test -p api` — 3 tests pass
- [x] 6.4 Test count before and after: 3 tests in both cases (original had 3 scene tests; no tests were lost)
