// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Globally shared Value Objects and Domain Primitives.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

/// A type alias for UUIDv7-based project identifiers.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct ProjectId(pub Uuid);

impl ProjectId {
    /// Create a new UUIDv7 `ProjectId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }
}

impl Default for ProjectId {
    fn default() -> Self {
        Self::new()
    }
}

/// Aggregate version for optimistic locking.
/// Holds a 64-bit version incremented on every state mutation inside the aggregate.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct AggregateVersion(pub u64);

impl AggregateVersion {
    /// Initial version applied on aggregate instantiation.
    pub const INITIAL: Self = Self(1);

    /// Increment the version by one.
    #[must_use]
    pub fn next(self) -> Self {
        Self(self.0 + 1)
    }
}

impl Default for AggregateVersion {
    fn default() -> Self {
        Self::INITIAL
    }
}
