// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Audit / journal Bounded Context (read side).
//!
//! Generic, cross-context audit projection. v1 captures the `membership`
//! Bounded Context's events; the schema is generic so other contexts can be
//! appended later without a breaking migration (see `block-membership` spec,
//! "Membership audit journal", and `design.md` decision 9.3). The `series_id`
//! tenant dimension is prepared for per-`SeriesId` tenancy (decision 9.2) but
//! is `NULL` in v1.

pub mod ports;
pub mod views;

pub use ports::AuditRepository;
pub use views::AuditEntry;
