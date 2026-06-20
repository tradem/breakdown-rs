// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Test helpers shared across the aggregate unit tests.
//!
//! This module is **only compiled in test builds** (`#[cfg(test)]`) so that
//! production code stays free of test doubles. See the `make_ctx` helper that
//! used to be duplicated in every `aggregate.rs` file.
//!
//! The helper constructs an empty `kameo_es::Context` with `'static` references
//! backed by `LazyLock` statics. It is constrained to aggregates whose
//! `Entity::Metadata` is `()` — which currently holds for all aggregates in
//! this crate. Should an aggregate with non-`()` metadata be introduced later,
//! add a dedicated helper instead of leaking test setup back into the domain
//! modules.

#![cfg(test)]

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::LazyLock;
use std::time::Instant;

use kameo_es::{Context, Entity, Metadata, StreamId};

/// Process-wide empty causation-tracking map shared by all test contexts.
type CausationTracking = HashMap<StreamId, (u64, HashSet<Cow<'static, str>>)>;

/// Builds a minimal, deterministic-enough `Context` for use in unit tests.
///
/// `metadata` and `causation_tracking` point at process-wide empty statics, so
/// every call returns a context that behaves like a fresh, causation-free
/// command execution. `time` / `executed_at` are set to "now" — tests that need
/// deterministic timestamps should assert on relative values, not absolute ones.
pub fn make_ctx<E>() -> Context<'static, E>
where
    E: Entity<Metadata = ()>,
{
    static META: LazyLock<Metadata<()>> = LazyLock::new(Metadata::default);
    static TRACKING: LazyLock<CausationTracking> = LazyLock::new(HashMap::new);
    Context {
        metadata: &META,
        causation_tracking: &TRACKING,
        time: chrono::Utc::now(),
        executed_at: Instant::now(),
    }
}
