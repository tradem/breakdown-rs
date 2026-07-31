// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Smoke test for the embedded seed configuration.
//!
//! The actual seeding logic (create/replay guard) is verified by
//! integration tests in `crates/integration-tests` that operate against
//! running PostgreSQL + SierraDB containers.

#[test]
fn test_embedded_seed_toml_parses_to_five_names() {
    let content = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../config/default_costume_categories.toml"
    ));
    let cfg: infra::sagas::season_seeding::DefaultCostumeCategoriesToml =
        toml::from_str(content).expect("embedded seed TOML must parse");
    assert_eq!(cfg.names.len(), 5);
    assert_eq!(cfg.names[0], "Oberteil");
    assert_eq!(cfg.names[4], "Accessoires");
}
