// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
//
// Architecture tests enforcing hexagonal boundary rules (ADR-017).
// Replaces the defunct arch_test-based guardrail (Issue #27).
//
// Layer 1 (dependency-level): checks that crates/core/Cargo.toml does NOT
// list forbidden infrastructure crate names as dependencies.
//
// Layer 2 (source-level): rust_arkitect ensures that no `.rs` file under
// crates/core/ uses `use` statements importing from infrastructure crates.
//
// Layer 3 (CI): cargo-deny (deny.toml) enforces general hygiene rules.
//
// Run: cargo test -p architecture_tests

use rust_arkitect::dsl::architectural_rules::ArchitecturalRules;
use rust_arkitect::dsl::arkitect::Arkitect;
use rust_arkitect::dsl::project::Project;

// ---------------------------------------------------------------------------
// Helper: find the workspace root (backend/ directory containing deny.toml).
// ---------------------------------------------------------------------------

fn workspace_root() -> String {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR must be set (runs via cargo test)");

    std::path::Path::new(&manifest_dir)
        .ancestors()
        .find(|p| p.join("deny.toml").exists())
        .expect("workspace root (with deny.toml) not found from manifest dir")
        .to_string_lossy()
        .into_owned()
}

// ---------------------------------------------------------------------------
// Layer 1 — Cargo.toml dependency-level enforcement
// ---------------------------------------------------------------------------

/// Forbidden crate names that must never appear as dependencies of
/// `breakdown_core` in its `Cargo.toml`.
const FORBIDDEN_CORE_DEPS: &[&str] = &["sqlx", "axum", "redis", "sierradb-client", "tokio"];

/// Path to the `breakdown_core` manifest, relative to the workspace root.
const CORE_CARGO_TOML: &str = "crates/core/Cargo.toml";

#[test]
fn core_cargo_toml_must_not_list_forbidden_dependencies() {
    let ws_root = workspace_root();
    let core_toml_path = std::path::Path::new(&ws_root).join(CORE_CARGO_TOML);
    let content = std::fs::read_to_string(&core_toml_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", core_toml_path.display()));

    let toml_value: toml::Value = content
        .parse()
        .unwrap_or_else(|e| panic!("failed to parse {}: {e}", core_toml_path.display()));

    // Collect all dependency key names from [dependencies] and [dev-dependencies].
    let mut violations: Vec<&str> = Vec::new();

    for section in &["dependencies", "dev-dependencies"] {
        if let Some(table) = toml_value.get(section).and_then(|v| v.as_table()) {
            for dep_name in table.keys() {
                if FORBIDDEN_CORE_DEPS.contains(&dep_name.as_str()) {
                    violations.push(dep_name.as_str());
                }
            }
        }
    }

    assert!(
        violations.is_empty(),
        "Forbidden dependencies found in {}: {:?}\n\
         breakdown_core must not depend on: {:?}\n\
         See ADR-017 for the architecture testing strategy.",
        CORE_CARGO_TOML,
        violations,
        FORBIDDEN_CORE_DEPS,
    );
}

// ---------------------------------------------------------------------------
// Layer 2 — Source-level enforcement via rust_arkitect
// ---------------------------------------------------------------------------

#[test]
fn core_must_not_depend_on_infrastructure_crates() {
    // rust_arkitect's `from_current_workspace()` only checks the manifest dir
    // and its immediate parent, but our workspace root is two levels up from
    // the architecture crate. Use `from_path` with the computed workspace root.
    let ws_root = workspace_root();
    let project = Project::from_path(&ws_root);

    // Define rules: breakdown_core must not depend on infrastructure crates
    let rules = ArchitecturalRules::define()
        .rules_for_crate("breakdown_core")
        .it_must_not_depend_on(&[
            "sqlx",
            "axum",
            "redis",
            "sierradb_client",
            "breakdown_infra",
            "api",
        ])
        .build();

    // Assert all rules pass
    let result = Arkitect::ensure_that(project).complies_with(rules);
    assert!(
        result.is_ok(),
        "Architecture violation: breakdown_core must not depend on infrastructure crates (see ADR-017).\n{:?}",
        result.err()
    );
}
