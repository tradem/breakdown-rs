// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::{ShootingSchedule, ShootingScheduleRow};
use breakdown_core::error::DomainError;
use chrono::NaiveDate;

/// Parse a flat, header-based shooting schedule without involving an LLM.
/// Supported headers are `scene_number`, `shooting_day_label`, `date`,
/// `location`, and `order`; unknown columns are ignored.
pub fn parse_schedule_csv(bytes: &[u8]) -> Result<ShootingSchedule, DomainError> {
    let mut reader = csv::ReaderBuilder::new()
        .flexible(true)
        .trim(csv::Trim::All)
        .from_reader(bytes);
    let headers = reader
        .headers()
        .map_err(|error| {
            DomainError::ValidationError(format!("invalid schedule CSV headers: {error}"))
        })?
        .clone();

    // Fail fast on a document with no supported header (wrong column names or
    // data-as-first-row): every value() lookup would otherwise return None and
    // the merge would later mark every row unmatched.
    const SUPPORTED_HEADERS: [&str; 6] = [
        "scene_number",
        "shooting_day_label",
        "shooting_day",
        "date",
        "location",
        "order",
    ];
    if !headers.iter().any(|header| {
        SUPPORTED_HEADERS
            .iter()
            .any(|supported| header.eq_ignore_ascii_case(supported))
    }) {
        return Err(DomainError::ValidationError(format!(
            "schedule CSV has no supported header; expected one of {}",
            SUPPORTED_HEADERS.join(", ")
        )));
    }

    let mut rows = Vec::new();
    for (index, record) in reader.records().enumerate() {
        let record = record.map_err(|error| {
            DomainError::ValidationError(format!("invalid schedule CSV row: {error}"))
        })?;
        let value = |name: &str| {
            headers
                .iter()
                .position(|header| header.eq_ignore_ascii_case(name))
                .and_then(|position| record.get(position))
                .map(str::trim)
                .filter(|value| !value.is_empty())
        };
        let scene_number = parse_optional_u32(value("scene_number"), "scene_number")?;
        let order = parse_optional_u32(value("order"), "order")?;
        let date = value("date")
            .map(|raw| {
                raw.parse::<NaiveDate>().map_err(|error| {
                    DomainError::ValidationError(format!("invalid schedule date {raw}: {error}"))
                })
            })
            .transpose()?;
        rows.push(ShootingScheduleRow {
            row_ref: format!("csv-{index}"),
            scene_number,
            shooting_day_label: value("shooting_day_label")
                .or_else(|| value("shooting_day"))
                .map(str::to_owned),
            date,
            location: value("location").map(str::to_owned),
            order,
        });
    }
    Ok(ShootingSchedule {
        block_id: None,
        rows,
    })
}

fn parse_optional_u32(value: Option<&str>, field: &str) -> Result<Option<u32>, DomainError> {
    value
        .map(|raw| {
            raw.parse::<u32>().map_err(|error| {
                DomainError::ValidationError(format!("invalid {field} value {raw}: {error}"))
            })
        })
        .transpose()
}
