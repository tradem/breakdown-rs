// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Globally shared Value Objects and Domain Primitives.

use serde::{Deserialize, Serialize};
use std::fmt;
use thiserror::Error;
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

/// Opaque identifier for a `CostumeCategory` aggregate.
///
/// A `CostumeCategory` is a season-scoped, user-editable vocabulary of part
/// types (Oberteil, Schuhe, …) used to categorise `CostumeDetail`s. Like the
/// other hierarchy ids it is a UUIDv7 opaque value type that is never decoded
/// inside `core`.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct CostumeCategoryId(pub Uuid);

impl CostumeCategoryId {
    /// Create a new UUIDv7 `CostumeCategoryId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    /// Construct from a raw `Uuid`.
    pub fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }
}

impl Default for CostumeCategoryId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for CostumeCategoryId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Opaque identifier for a `ShootingDay` aggregate.
///
/// A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its
/// own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that
/// is never decoded inside `core`.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(transparent)]
pub struct ShootingDayId(pub Uuid);

impl ShootingDayId {
    /// Create a new UUIDv7 `ShootingDayId`.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    /// Construct from a raw `Uuid`.
    pub fn from_uuid(id: Uuid) -> Self {
        Self(id)
    }
}

impl Default for ShootingDayId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for ShootingDayId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::str::FromStr for ShootingDayId {
    type Err = uuid::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(Self(Uuid::from_str(s)?))
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

/// A validated, lexicographically-sortable key used for ordering entities
/// (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.
///
/// The key is a non-empty string over a fixed printable-ASCII alphabet
/// (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of
/// its own beyond raw byte/lexicographic order, which matches the SQL
/// `ORDER BY order_key ASC` semantics of the read model. To insert an entity
/// between two existing siblings, use [`LexicalSortKey::midpoint`], which
/// produces a key strictly between the two in exactly one event.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct LexicalSortKey(pub String);

/// Smallest byte value of the fixed printable-ASCII alphabet (`'!'`, `0x21`).
const LEXICAL_MIN_BYTE: u8 = b'!';
/// Largest byte value of the fixed printable-ASCII alphabet (`'~'`, `0x7E`).
const LEXICAL_MAX_BYTE: u8 = b'~';
/// Bounded length to stop pathological key growth under repeated midpoints.
const LEXICAL_MAX_LEN: usize = 64;

/// Validation / generation errors for [`LexicalSortKey`].
#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum LexicalSortKeyError {
    /// The key must not be empty.
    #[error("LexicalSortKey must not be empty")]
    Empty,
    /// The key contains a character outside the printable-ASCII alphabet.
    #[error("LexicalSortKey contains a character outside the printable-ASCII alphabet")]
    InvalidChar,
    /// The key exceeds the bounded length.
    #[error("LexicalSortKey exceeds the maximum length of {0}")]
    TooLong(usize),
    /// No key fits strictly between the two bounds (degenerate case;
    /// a compaction pass is required).
    #[error("no LexicalSortKey fits between the given bounds; compaction required")]
    NoRoom,
}

impl LexicalSortKey {
    /// Construct a `LexicalSortKey`, validating the fixed-alphabet / length rules.
    pub fn new(s: impl Into<String>) -> Result<Self, LexicalSortKeyError> {
        let s = s.into();
        if s.is_empty() {
            return Err(LexicalSortKeyError::Empty);
        }
        if s.len() > LEXICAL_MAX_LEN {
            return Err(LexicalSortKeyError::TooLong(LEXICAL_MAX_LEN));
        }
        if !s
            .bytes()
            .all(|b| (LEXICAL_MIN_BYTE..=LEXICAL_MAX_BYTE).contains(&b))
        {
            return Err(LexicalSortKeyError::InvalidChar);
        }
        Ok(Self(s))
    }

    /// Construct a `LexicalSortKey`, panicking on invalid input.
    ///
    /// Intended for `const`-friendly seeds and tests where the literal is known
    /// to be valid.
    pub fn from_static(s: &'static str) -> Self {
        Self::new(s).expect("static LexicalSortKey must be valid")
    }

    /// Produce a key strictly between `a` and `b` (`a < result < b`).
    ///
    /// Uses a fractional-key algorithm over the fixed alphabet:
    /// - If `a` is a prefix of `b`, append the alphabet's minimum character.
    /// - If the differing bytes are adjacent (`b[i] == a[i] + 1`), append the
    ///   alphabet's minimum character to `a`.
    /// - Otherwise (`b[i] - a[i] >= 2`) emit `a[i] + 1` at the differing
    ///   position, which is strictly between the two.
    ///
    /// Returns [`LexicalSortKeyError::NoRoom`] when both bounds are already at
    /// maximum length with no gap (the degenerate case a compaction pass must
    /// resolve).
    pub fn midpoint(a: &Self, b: &Self) -> Result<Self, LexicalSortKeyError> {
        if a.0.is_empty() || b.0.is_empty() {
            return Err(LexicalSortKeyError::Empty);
        }
        if a.0 >= b.0 {
            // No strict ordering → no key can sit strictly between them.
            return Err(LexicalSortKeyError::NoRoom);
        }
        let av = a.0.as_bytes();
        let bv = b.0.as_bytes();

        // Longest common prefix.
        let mut i = 0;
        while i < av.len() && i < bv.len() && av[i] == bv[i] {
            i += 1;
        }
        let prefix = &a.0[..i];

        if i < av.len() && i < bv.len() {
            // Both bounds have a byte at `i`, with `av[i] < bv[i]`.
            let (lo, hi) = (av[i], bv[i]);
            if hi > lo + 1 {
                // Gap of >= 2: a single character strictly between the two.
                let mut c = String::with_capacity(i + 1);
                c.push_str(prefix);
                c.push(char::from_u32((lo + 1) as u32).expect("alphabet byte is valid char"));
                return Self::new(c);
            }
            // Adjacent bytes: append the alphabet minimum to `a`.
            let mut c = a.0.clone();
            c.push(char::from_u32(LEXICAL_MIN_BYTE as u32).expect("alphabet byte is valid char"));
            return Self::new(c);
        }

        // `a` is a strict prefix of `b`: extend `a` with the alphabet minimum.
        // The result is `a + min` < `b` (it is a strict prefix of `b`) and > `a`.
        let mut c = a.0.clone();
        c.push(char::from_u32(LEXICAL_MIN_BYTE as u32).expect("alphabet byte is valid char"));
        Self::new(c)
    }
}

impl std::fmt::Display for LexicalSortKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

#[cfg(test)]
#[path = "shared_test.rs"]
mod tests;
