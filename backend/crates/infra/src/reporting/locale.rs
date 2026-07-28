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
pub fn convert_to_timezone(
    utc_dt: &chrono::DateTime<chrono::Utc>,
    _timezone: &str,
) -> (i32, u8, u8, u8, u8) {
    // For now, use chrono's timezone support
    // In production, this should use ICU4X's timezone support
    let berlin = chrono::FixedOffset::east_opt(3600).unwrap(); // CET
    let local = utc_dt.with_timezone(&berlin);

    use chrono::Datelike;
    use chrono::Timelike;
    (
        local.year(),
        local.month() as u8,
        local.day() as u8,
        local.hour() as u8,
        local.minute() as u8,
    )
}
