// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The one `jiff` ↔ `sqlx` bridge of the write and read sides (ADR-040,
//! issue #929).
//!
//! `sqlx` 0.9 maps `timestamptz`, `timestamp` and `date` only through the
//! `chrono` or `time` feature — it has no `jiff` integration. Rust's orphan
//! rules forbid us from implementing `Type`/`Encode`/`Decode` for
//! `jiff::Timestamp` directly (trait, type and `Postgres` are all foreign), so
//! the mapping lives in the companion crate `jiff-sqlx`, published from the
//! `jiff` repository itself and tracking `sqlx ^0.9`. It supplies wrapper
//! types that carry the real `timestamptz`/`date` OIDs — this module is the
//! single place where a row value crosses between those wrappers and the
//! domain types, so no call site has to spell `jiff_sqlx::` out and a future
//! upstream `sqlx` feature only has to change these six functions.
//!
//! Precision is preserved end to end: `timestamptz` is microsecond-precision
//! in PostgreSQL and `jiff::Timestamp` is nanosecond-precision, so a round trip
//! truncates to the same microsecond bucket chrono's mapping used. Nothing is
//! stored as text — the columns keep their native type and the wire `date-time`
//! format is unchanged (the `openapi_drift` test guards the contract side).

use jiff::{Timestamp, civil::Date};
pub use jiff_sqlx::Date as SqlDate;
pub use jiff_sqlx::Timestamp as SqlTimestamp;
use sqlx::{Row, postgres::PgRow};

/// Decodes a `timestamptz` column into the domain instant.
#[must_use]
pub fn ts(value: SqlTimestamp) -> Timestamp {
    value.to_jiff()
}

/// `Option`-preserving [`ts`], for nullable `timestamptz` columns.
#[must_use]
pub fn ts_opt(value: Option<SqlTimestamp>) -> Option<Timestamp> {
    value.map(ts)
}

/// Encodes a domain instant for a `timestamptz` column or bind parameter.
#[must_use]
pub fn sql_ts(value: Timestamp) -> SqlTimestamp {
    SqlTimestamp::from(value)
}

/// `Option`-preserving [`sql_ts`].
#[must_use]
pub fn sql_ts_opt(value: Option<Timestamp>) -> Option<SqlTimestamp> {
    value.map(sql_ts)
}

/// Decodes a `date` column into a civil date.
#[must_use]
pub fn date(value: SqlDate) -> Date {
    value.to_jiff()
}

/// `Option`-preserving [`date`], for nullable `date` columns.
#[must_use]
pub fn date_opt(value: Option<SqlDate>) -> Option<Date> {
    value.map(date)
}

/// Encodes a civil date for a `date` column or bind parameter.
#[must_use]
pub fn sql_date(value: Date) -> SqlDate {
    SqlDate::from(value)
}

/// `Option`-preserving [`sql_date`].
#[must_use]
pub fn sql_date_opt(value: Option<Date>) -> Option<SqlDate> {
    value.map(sql_date)
}

/// Column accessors for the two temporal column types, so a row mapping reads
/// `row.get_ts("updated_at")` instead of a `try_get::<jiff_sqlx::Timestamp, _>`
/// turbofish plus a conversion at every one of the ~130 call sites.
pub trait PgRowTimeExt {
    /// `timestamptz` → [`Timestamp`].
    fn get_ts(&self, column: &str) -> Result<Timestamp, sqlx::Error>;
    /// Nullable `timestamptz` → `Option<Timestamp>`.
    fn get_ts_opt(&self, column: &str) -> Result<Option<Timestamp>, sqlx::Error>;
    /// `date` → [`Date`].
    fn get_date(&self, column: &str) -> Result<Date, sqlx::Error>;
    /// Nullable `date` → `Option<Date>`.
    fn get_date_opt(&self, column: &str) -> Result<Option<Date>, sqlx::Error>;
}

impl PgRowTimeExt for PgRow {
    fn get_ts(&self, column: &str) -> Result<Timestamp, sqlx::Error> {
        self.try_get::<SqlTimestamp, _>(column).map(ts)
    }

    fn get_ts_opt(&self, column: &str) -> Result<Option<Timestamp>, sqlx::Error> {
        self.try_get::<Option<SqlTimestamp>, _>(column).map(ts_opt)
    }

    fn get_date(&self, column: &str) -> Result<Date, sqlx::Error> {
        self.try_get::<SqlDate, _>(column).map(date)
    }

    fn get_date_opt(&self, column: &str) -> Result<Option<Date>, sqlx::Error> {
        self.try_get::<Option<SqlDate>, _>(column).map(date_opt)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The bridge must be an identity on the domain type — a lossy
    /// implementation would silently shift every projected `updated_at`.
    #[test]
    fn timestamp_round_trip_is_lossless_at_microsecond_precision() {
        // PostgreSQL `timestamptz` stores microseconds; jiff carries nanos.
        let instant: Timestamp = "2026-11-17T12:49:25.123456Z".parse().expect("valid");

        assert_eq!(ts(sql_ts(instant)), instant);
    }

    #[test]
    fn nullable_columns_keep_none() {
        assert_eq!(ts_opt(None), None);
        assert_eq!(sql_ts_opt(None), None);
        assert_eq!(date_opt(None), None);
        assert_eq!(sql_date_opt(None), None);
    }

    #[test]
    fn date_round_trip_is_lossless() {
        let day: Date = "2026-01-02".parse().expect("valid");

        assert_eq!(date(sql_date(day)), day);
    }
}
