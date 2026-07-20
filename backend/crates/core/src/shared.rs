// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Globally shared Value Objects and Domain Primitives.

use serde::{Deserialize, Serialize};
use std::fmt;
use utoipa::ToSchema;
use uuid::Uuid;

/// Opaque identifier for a user, wrapping the OIDC `sub` claim.
///
/// `UserId` references the authenticated principal without ever decoding,
/// storing, or dereferencing identity attributes in `core`. The backend only
/// trusts the IdP-issued `sub`; account lifecycle lives exclusively in the
/// OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a
/// UUIDv7 — it is the raw string subject the IdP assigns.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct UserId(pub String);

impl UserId {
    /// Construct a `UserId` from an OIDC `sub` claim string.
    pub fn from_sub(sub: impl Into<String>) -> Self {
        Self(sub.into())
    }

    /// Borrow the underlying `sub` string.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for UserId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::str::FromStr for UserId {
    type Err = std::convert::Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(Self(s.to_string()))
    }
}

/// Opaque identifier for a `Series` (a show run).
///
/// `SeriesId` is an opaque UUIDv7 value type introduced by the
/// `introduce-season-block-episode-hierarchy` change. It is the seam for a
/// future additive `Series` aggregate: every hierarchy entity (Season, Block,
/// Episode) references it but no `Series` aggregate exists yet.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct SeriesId(pub Uuid);

impl SeriesId {
    /// Create a new UUIDv7 `SeriesId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    /// Construct from a raw `Uuid`.
    pub fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }
}

impl Default for SeriesId {
    fn default() -> Self {
        Self::new()
    }
}

/// Opaque identifier for a `Season` aggregate.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct SeasonId(pub Uuid);

impl SeasonId {
    /// Create a new UUIDv7 `SeasonId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    /// Construct from a raw `Uuid`.
    pub fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }
}

impl Default for SeasonId {
    fn default() -> Self {
        Self::new()
    }
}

/// Opaque identifier for a `Block` aggregate.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct BlockId(pub Uuid);

impl BlockId {
    /// Create a new UUIDv7 `BlockId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    /// Construct from a raw `Uuid`.
    pub fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }
}

impl Default for BlockId {
    fn default() -> Self {
        Self::new()
    }
}

/// Opaque identifier for an `Episode` aggregate.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct EpisodeId(pub Uuid);

impl EpisodeId {
    /// Create a new UUIDv7 `EpisodeId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    /// Construct from a raw `Uuid`.
    pub fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }
}

impl Default for EpisodeId {
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
#[path = "shared_test.rs"]
mod tests;
