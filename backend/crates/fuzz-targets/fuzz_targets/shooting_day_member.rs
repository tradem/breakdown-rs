// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Fuzz target for deserialization of request bodies with complex enums:
//! `CreateShootingDayRequest` (ShootingDaySource) and `InviteMemberRequest`
//! (Role).  Tests that externally-tagged enums with inner data don't panic
//! on any byte sequence.

#![cfg_attr(fuzzing, no_main)]

use libfuzzer_sys::fuzz_target;

use chrono::NaiveDate;
use serde::Deserialize;

use breakdown_core::membership::Role;
use breakdown_core::shared::{EpisodeId, LexicalSortKey, ShootingDayId};
use breakdown_core::shooting_day::events::ShootingDaySource;

/// Mirrors `breakdown_api::handlers::CreateShootingDayRequest`.
#[derive(Debug, Deserialize)]
struct CreateShootingDayRequest {
    episode_id: EpisodeId,
    label: Option<String>,
    order_key: LexicalSortKey,
    date: Option<NaiveDate>,
    source: ShootingDaySource,
}

/// Mirrors `breakdown_api::handlers::InviteMemberRequest`.
#[derive(Debug, Deserialize)]
struct InviteMemberRequest {
    user_id: String,
    role: Role,
}

/// Mirrors `breakdown_api::handlers::GrantRoleRequest`.
#[derive(Debug, Deserialize)]
struct GrantRoleRequest {
    role: Role,
}

fuzz_target!(|data: &[u8]| {
    // ── ShootingDay ────────────────────────────────────────────────────
    if let Ok(req) = serde_json::from_slice::<CreateShootingDayRequest>(data) {
        let _ = req.episode_id.0;
        let _ = req.label.as_deref();
        let _ = req.order_key.0.len();
        let _ = req.date;

        // ShootingDaySource is an externally-tagged enum — check all arms
        match &req.source {
            ShootingDaySource::Manual => {}
            ShootingDaySource::AiExtracted {
                document_id,
                external_ref,
                confidence,
            } => {
                let _ = document_id;
                let _ = external_ref.as_deref();
                let _ = confidence.is_finite();
            }
        }

        let _cmd = breakdown_core::shooting_day::commands::CreateShootingDay {
            id: ShootingDayId::new(),
            episode_id: req.episode_id,
            label: req.label,
            order_key: req.order_key,
            date: req.date,
            source: req.source,
        };
    }

    // ── InviteMember ───────────────────────────────────────────────────
    if let Ok(req) = serde_json::from_slice::<InviteMemberRequest>(data) {
        let _ = req.user_id.len();
        match req.role {
            Role::CostumeDesigner | Role::WardrobeSupervisor | Role::CostumeAssistant => {}
        }

        let _cmd = breakdown_core::membership::commands::InviteMember {
            block_id: breakdown_core::shared::BlockId::from_uuid(uuid::Uuid::now_v7()),
            user_id: breakdown_core::shared::UserId::from_sub(req.user_id),
            role: req.role,
        };
    }

    // ── GrantRole (same Role enum — fuzzes rename_all = "snake_case") ──
    if let Ok(req) = serde_json::from_slice::<GrantRoleRequest>(data) {
        match req.role {
            Role::CostumeDesigner | Role::WardrobeSupervisor | Role::CostumeAssistant => {}
        }
    }
});
