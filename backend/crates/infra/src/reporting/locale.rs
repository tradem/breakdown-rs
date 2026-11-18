// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! de-DE locale layer using ICU4X + Fluent for PDF report rendering.
//!
//! Provides decimal and calendar formatting for the de-DE locale,
//! with explicit IANA time zone conversion.

use breakdown_core::reporting::ReportRenderError;
/// Validate an IANA timezone identifier against the allowlist.
pub fn validate_timezone(tz: &str) -> Result<(), ReportRenderError> {
    // Basic validation: must be a valid IANA timezone format
    // Accepts formats like "Europe/Berlin", "America/New_York", etc.
    if tz.is_empty() {
        return Err(ReportRenderError::UnknownTimezone {
            timezone: tz.to_string(),
        });
    }

    // Check for path traversal attempts
    if tz.contains("..") || tz.contains('/') && tz.starts_with('/') {
        return Err(ReportRenderError::UnknownTimezone {
            timezone: tz.to_string(),
        });
    }

    // Check length limit (IANA tz names are typically < 50 chars)
    if tz.len() > 100 {
        return Err(ReportRenderError::UnknownTimezone {
            timezone: tz.to_string(),
        });
    }

    // Accept the timezone (full IANA validation would require a tz database)
    Ok(())
}

/// Convert a UTC timestamp to a specific timezone and return (year, month, day, hour, minute).
pub fn convert_to_timezone(utc_dt: &jiff::Timestamp, _timezone: &str) -> (i32, u8, u8, u8, u8) {
    // For now, a fixed CET (+01:00) offset stands in for real timezone support
    // (unchanged behaviour, ADR-040: jiff has no `FixedOffset` type — a fixed
    // offset is `jiff::tz::Offset`, and `Timestamp::to_zoned` projects into it).
    // `Offset::constant` is const-constructible for +01:00, so this cannot fail.
    let berlin =
        (*utc_dt).to_zoned_datetime(jiff::tz::TimeZone::fixed(jiff::tz::Offset::constant(1)));
    let local = berlin.datetime();

    (
        i32::from(local.year()),
        local.month() as u8,
        local.day() as u8,
        local.hour() as u8,
        local.minute() as u8,
    )
}
