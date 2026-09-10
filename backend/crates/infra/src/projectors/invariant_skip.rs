// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Projector-side failure behavior for cross-aggregate uniqueness
//! invariants (issue #404; doctrine in `AGENTS.md` §1).
//!
//! A permanent 23505 unique-violation on a projection constraint that
//! authoritatively enforces a cross-aggregate invariant is a *poison event*:
//! the write path accepted the violating command (pre-#404, or via a
//! pre-check race that the constraint legitimately wins), so the event can
//! never be projected. Per the doctrine it must **never** panic-kill the
//! projector worker/coordinator — it is classified, logged, and skipped.
//!
//! The processor batches events into one transaction and commits at flush;
//! a failed statement would abort the whole batch. Every guarded insert
//! therefore runs inside a SAVEPOINT (`(&mut *ctx).begin()` on the batch
//! transaction): on a matching unique violation the savepoint is rolled back
//! and the event is acknowledged (skipped); any other error propagates
//! unchanged and keeps the existing retry semantics.
//!
//! Full dead-letter/poison-table mechanics with health signals are specced
//! in issue #37 (minimal poison handling); this module is the #404 minimal
//! path: classify + log + skip.

/// Authoritative projection constraint names — the #404 invariant backstops.
/// A 23505 on exactly these constraints is a *permanent* violation that the
/// projectors skip instead of propagating.
pub(crate) const SCENE_SHOOT_PAIR_CONSTRAINT: &str = "uq_projection_scene_shoot_pair";
pub(crate) const SEASON_NUMBER_CONSTRAINT: &str = "idx_projection_season_series_number";
pub(crate) const BLOCK_NUMBER_CONSTRAINT: &str = "idx_projection_block_series_number";
pub(crate) const EPISODE_NUMBER_CONSTRAINT: &str = "idx_projection_episode_series_number";

/// Returns `true` if `err` is a Postgres unique-violation (SQLSTATE 23505) on
/// the named constraint — the signature of a *permanent* invariant violation.
/// Both conditions must hold: a matching constraint name alone (e.g. on a
/// 23502 not-null or 23503 FK violation carrying a constraint name) must NOT
/// classify as an invariant violation.
pub(crate) fn is_unique_violation_on(err: &sqlx::Error, constraint: &str) -> bool {
    err.as_database_error().is_some_and(|db| {
        db.code().as_deref() == Some("23505") && db.constraint() == Some(constraint)
    })
}

#[cfg(test)]
mod tests {
    use super::is_unique_violation_on;
    use sqlx::error::DatabaseError;
    use std::error::Error as StdError;

    /// Minimal stand-in for a Postgres 23505 `DatabaseError` so the
    /// classification can be tested without a live database.
    #[derive(Debug)]
    struct FakeDbError {
        code: String,
        constraint: Option<String>,
    }

    impl std::fmt::Display for FakeDbError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            write!(f, "db error {}", self.code)
        }
    }

    impl std::error::Error for FakeDbError {}

    impl DatabaseError for FakeDbError {
        fn message(&self) -> &str {
            "duplicate key value violates unique constraint"
        }
        fn code(&self) -> Option<std::borrow::Cow<'_, str>> {
            Some(std::borrow::Cow::Borrowed(&self.code))
        }
        fn constraint(&self) -> Option<&str> {
            self.constraint.as_deref()
        }
        fn kind(&self) -> sqlx::error::ErrorKind {
            sqlx::error::ErrorKind::UniqueViolation
        }
        fn as_error(&self) -> &(dyn StdError + Send + Sync + 'static) {
            self
        }
        fn as_error_mut(&mut self) -> &mut (dyn StdError + Send + Sync + 'static) {
            self
        }
        fn into_error(self: Box<Self>) -> Box<dyn StdError + Send + Sync + 'static> {
            self
        }
    }

    fn unique_violation(constraint: Option<&str>) -> sqlx::Error {
        db_error("23505", constraint)
    }

    /// Arbitrary-SQLSTATE database error (code + optional constraint name).
    fn db_error(code: &str, constraint: Option<&str>) -> sqlx::Error {
        sqlx::Error::Database(Box::new(FakeDbError {
            code: code.to_owned(),
            constraint: constraint.map(str::to_owned),
        }))
    }

    /// Kills `replace is_unique_violation_on -> ... with false`: a 23505 on
    /// the authoritative constraint must be classified as an invariant
    /// violation (the mutant would propagate it and panic-kill the worker).
    #[test]
    fn classifies_unique_violation_on_matching_constraint() {
        assert!(is_unique_violation_on(
            &unique_violation(Some("uq_projection_scene_shoot_pair")),
            "uq_projection_scene_shoot_pair"
        ));
    }

    /// A different constraint (e.g. another aggregate's numbering index) is
    /// NOT this invariant's backstop and must propagate as a real error.
    #[test]
    fn does_not_classify_other_constraint() {
        assert!(!is_unique_violation_on(
            &unique_violation(Some("idx_projection_season_series_number")),
            "uq_projection_scene_shoot_pair"
        ));
    }

    /// Negative test (CodeRabbit #406 review): the SAME constraint name with
    /// a different SQLSTATE (e.g. 23502 not-null, which also carries a
    /// constraint name) must NOT classify as an invariant violation — the
    /// error must propagate instead of being skipped.
    #[test]
    fn does_not_classify_other_sqlstate_with_matching_constraint() {
        assert!(!is_unique_violation_on(
            &db_error("23502", Some("uq_projection_scene_shoot_pair")),
            "uq_projection_scene_shoot_pair"
        ));
        assert!(!is_unique_violation_on(
            &db_error("23000", Some("uq_projection_scene_shoot_pair")),
            "uq_projection_scene_shoot_pair"
        ));
    }

    /// A unique violation without a constraint name (or any other error
    /// shape) is not classifiable and must propagate.
    #[test]
    fn does_not_classify_missing_constraint_or_other_error() {
        assert!(!is_unique_violation_on(
            &unique_violation(None),
            "uq_projection_scene_shoot_pair"
        ));
        assert!(!is_unique_violation_on(
            &sqlx::Error::RowNotFound,
            "uq_projection_scene_shoot_pair"
        ));
    }
}
