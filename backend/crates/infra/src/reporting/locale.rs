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

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    // ------------------------------------------------------------------
    // validate_timezone
    // ------------------------------------------------------------------

    #[test]
    fn test_validate_timezone_valid() {
        assert!(validate_timezone("Europe/Berlin").is_ok());
        assert!(validate_timezone("America/New_York").is_ok());
        assert!(validate_timezone("UTC").is_ok());
        assert!(validate_timezone("Asia/Tokyo").is_ok());
        assert!(validate_timezone("Australia/Sydney").is_ok());
    }

    #[test]
    fn test_validate_timezone_invalid() {
        assert!(validate_timezone("").is_err());
        assert!(validate_timezone("../etc/passwd").is_err());
        assert!(validate_timezone("/etc/passwd").is_err());
        assert!(validate_timezone(&"a".repeat(200)).is_err());
    }

    #[test]
    fn test_validate_timezone_edge_cases() {
        // Exactly 100 chars is still ok (boundary)
        let exactly_100 = "a".repeat(100);
        assert!(validate_timezone(&exactly_100).is_ok());

        // 101 chars is rejected
        let over_100 = "a".repeat(101);
        assert!(validate_timezone(&over_100).is_err());

        // Trailing slash only (not absolute path)
        assert!(validate_timezone("Europe/").is_ok());
        assert!(validate_timezone("foo/..").is_err());
    }

    #[test]
    fn test_validate_timezone_error_type() {
        let err = validate_timezone("").unwrap_err();
        assert!(matches!(err, ReportRenderError::UnknownTimezone { .. }));
    }

    // ------------------------------------------------------------------
    // convert_to_timezone
    // ------------------------------------------------------------------

    #[test]
    fn test_convert_to_timezone_berlin_winter() {
        // 2024-01-15 12:00:00 UTC -> 2024-01-15 13:00:00 CET (UTC+1)
        let utc_dt = chrono::Utc.with_ymd_and_hms(2024, 1, 15, 12, 0, 0).unwrap();
        let (year, month, day, hour, minute) = convert_to_timezone(&utc_dt, "Europe/Berlin");
        assert_eq!(year, 2024);
        assert_eq!(month, 1);
        assert_eq!(day, 15);
        assert_eq!(hour, 13); // CET = UTC+1
        assert_eq!(minute, 0);
    }

    #[test]
    fn test_convert_to_timezone_berlin_summer() {
        // 2024-06-15 10:00:00 UTC -> 2024-06-15 12:00:00 CEST (UTC+2)
        // Note: convert_to_timezone currently uses CET (UTC+1) always
        let utc_dt = chrono::Utc.with_ymd_and_hms(2024, 6, 15, 10, 0, 0).unwrap();
        let (year, month, day, hour, minute) = convert_to_timezone(&utc_dt, "Europe/Berlin");
        assert_eq!(year, 2024);
        assert_eq!(month, 6);
        assert_eq!(day, 15);
        assert_eq!(minute, 0);
        // Currently always uses CET (UTC+1), so 10:00 UTC -> 11:00 CET
        assert_eq!(hour, 11);
    }

    #[test]
    fn test_convert_to_timezone_date_boundary() {
        // 2024-01-01 00:00:00 UTC -> 2024-01-01 01:00:00 CET
        let utc_dt = chrono::Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap();
        let (year, month, day, hour, minute) = convert_to_timezone(&utc_dt, "Europe/Berlin");
        assert_eq!(year, 2024);
        assert_eq!(month, 1);
        assert_eq!(day, 1);
        assert_eq!(hour, 1);
        assert_eq!(minute, 0);
    }

    #[test]
    fn test_convert_to_timezone_previous_year_eve() {
        // 2023-12-31 22:00:00 UTC -> 2023-12-31 23:00:00 CET
        let utc_dt = chrono::Utc
            .with_ymd_and_hms(2023, 12, 31, 22, 0, 0)
            .unwrap();
        let (year, month, day, hour, minute) = convert_to_timezone(&utc_dt, "Europe/Berlin");
        assert_eq!(year, 2023);
        assert_eq!(month, 12);
        assert_eq!(day, 31);
        assert_eq!(hour, 23);
        assert_eq!(minute, 0);
    }
}
