// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Shared test helpers for unit and integration tests.
//!
//! Provides deterministic test fixtures such as [`make_ctx`] for use in
//! aggregate unit tests and integration round-trips without exposing
//! test-only code through the production API.

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::LazyLock;
use std::time::Instant;

use kameo_es::{Context, Entity, Metadata, StreamId};

/// Process-wide empty causation-tracking map shared by all test contexts.
type CausationTracking = HashMap<StreamId, (u64, HashSet<Cow<'static, str>>)>;

/// Builds a minimal, deterministic-enough `Context` for use in unit and
/// integration tests.
///
/// `metadata` and `causation_tracking` point at process-wide empty statics,
/// so every call returns a context that behaves like a fresh, causation-free
/// command execution. `time` / `executed_at` are set to "now" — tests that
/// need deterministic timestamps should assert on relative values.
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
