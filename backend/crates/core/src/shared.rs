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
///
/// The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`,
/// and every mutation increments the version by one.
///
/// The SierraDB stream version (0-based) is an infrastructure-internal detail.
/// The translation rule is: `domain_version = stream_version + 1`
/// (and inversely `stream_version = domain_version - 1`) which is performed
/// exclusively inside `crates::infra` at the `*Commands` adapter boundary.
/// `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_is_one() {
        assert_eq!(AggregateVersion::INITIAL.0, 1);
    }

    #[test]
    fn next_increments_by_one() {
        let v0 = AggregateVersion::INITIAL;
        let v1 = v0.next();
        assert_eq!(v1.0, 2);

        let v2 = v1.next();
        assert_eq!(v2.0, 3);
    }

    #[test]
    fn default_is_initial() {
        assert_eq!(AggregateVersion::default(), AggregateVersion::INITIAL);
    }
}
