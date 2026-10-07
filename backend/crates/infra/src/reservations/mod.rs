// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

//! ES-native reservation streams (ADR-036, issue #586): atomic
//! cross-aggregate uniqueness at the write boundary for the four #404
//! invariants — episode/season/block numbering `(series_id, number)` and
//! scene_shoot pair-uniqueness `(scene_id, shooting_day_id)` — on synthetic
//! SierraDB streams (`reservation-*`, category `reservation`).
//!
//! Doctrine mapping: the projection unique constraints stay the authoritative
//! backstop (#404 savepoint-skips remain), the API-edge pre-checks stay
//! advisory and cheap; the reservation claim closes the pre-check-to-append
//! race window (a racing command now answers the registered 409 *before*
//! touching the aggregate stream instead of winning a 2xx with an
//! unprojectable event). Compensation is release-event + reaper (ADR-036 §3).

pub mod event;
pub mod reaper;
pub mod store;
