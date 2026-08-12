// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

//! Bundle-coverage lint (ADR-031 D5, error-localization spec).
//!
//! 1. Every registered problem code has a Fluent message in **every active
//!    locale** (`de`, `en`) — a new code without its `de`/`en` message fails
//!    CI, naming the code and the missing locale.
//! 2. Every bundle key maps to an existing (or deprecated) registry code —
//!    orphan keys fail CI, preventing drift after code deprecation.
//!
//! The key derivation is the deterministic 1:1 transform
//! `{code}` → `problem-{code with dashes}` (also enforced by
//! `ProblemCode::message_key`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

use std::collections::HashSet;

use breakdown_core::error_registry::{PROBLEM_CODES, problem_code};
use fluent_bundle::FluentResource;
use fluent_syntax::ast::Entry;

/// Message ids in a bundle (the raw FTL entry names).
fn bundle_keys(source: &str) -> HashSet<String> {
    let resource = FluentResource::try_new(source.to_owned()).expect("bundle must parse");
    resource
        .entries()
        .filter_map(|entry| match entry {
            Entry::Message(message) => Some(message.id.name.to_string()),
            Entry::Term(_)
            | Entry::Comment(_)
            | Entry::GroupComment(_)
            | Entry::ResourceComment(_)
            | Entry::Junk { .. } => None,
        })
        .collect()
}

#[test]
fn every_registered_code_has_messages_in_all_active_locales() {
    let locales = [
        ("de", include_str!("../locales/de/errors.ftl")),
        ("en", include_str!("../locales/en/errors.ftl")),
    ];

    let mut failures: Vec<String> = Vec::new();
    for (locale, source) in locales {
        let keys = bundle_keys(source);
        for entry in PROBLEM_CODES {
            let key = entry.message_key();
            if !keys.contains(&key) {
                failures.push(format!(
                    "code `{}` has no `{locale}` message (expected key `{key}`)",
                    entry.code
                ));
            }
        }
    }

    assert!(
        failures.is_empty(),
        "Bundle coverage gaps ({count}):\n{failures}",
        count = failures.len(),
        failures = failures.join("\n")
    );
}

#[test]
fn every_bundle_key_maps_to_a_registered_code() {
    let locales = [
        ("de", include_str!("../locales/de/errors.ftl")),
        ("en", include_str!("../locales/en/errors.ftl")),
    ];

    // The allowed key set is derived *forward* from the registry: the
    // reverse transform is ambiguous (codes contain dashes inside segments),
    // so the registry is the single source for both directions.
    // Deprecated codes keep their messages until removal (ADR-031); the
    // registry has no deprecated entries yet — extend this set when the
    // first code is deprecated.
    let registry_keys: HashSet<String> = PROBLEM_CODES.iter().map(|e| e.message_key()).collect();

    let mut failures: Vec<String> = Vec::new();
    for (locale, source) in locales {
        for key in bundle_keys(source) {
            if !registry_keys.contains(&key) {
                failures.push(format!(
                    "`{locale}`: orphan message key `{key}` — no registry code"
                ));
            }
        }
    }

    assert!(
        failures.is_empty(),
        "Orphan bundle keys ({count}):\n{failures}",
        count = failures.len(),
        failures = failures.join("\n")
    );
}

/// The deterministic key derivation matches `ProblemCode::message_key`.
#[test]
fn message_key_derivation_is_deterministic() {
    assert_eq!(
        PROBLEM_CODES[0].message_key(),
        problem_code(PROBLEM_CODES[0].code)
            .expect("registered")
            .message_key()
    );
}
