// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! CostumeCategory commands.

use uuid::Uuid;

use crate::shared::{AggregateVersion, LexicalSortKey, SeasonId, SeriesId};

/// Create a season-scoped costume category with an externally supplied UUIDv7 id.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// season projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct CreateCostumeCategory {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub series_id: Option<SeriesId>,
    pub name: String,
    pub order_key: LexicalSortKey,
}

/// Rename a costume category.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// category projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct RenameCostumeCategory {
    pub id: Uuid,
    pub name: String,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Reorder a costume category.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// category projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ReorderCostumeCategory {
    pub id: Uuid,
    pub order_key: LexicalSortKey,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Archive a costume category.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// category projection, never queried again by the command adapter.
#[derive(Debug, Clone, serde::Deserialize, utoipa::ToSchema)]
pub struct ArchiveCostumeCategory {
    pub id: Uuid,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for CreateCostumeCategory {
    fn command_name() -> &'static str {
        "CreateCostumeCategory"
    }
}
impl kameo_es::CommandName for RenameCostumeCategory {
    fn command_name() -> &'static str {
        "RenameCostumeCategory"
    }
}
impl kameo_es::CommandName for ReorderCostumeCategory {
    fn command_name() -> &'static str {
        "ReorderCostumeCategory"
    }
}
impl kameo_es::CommandName for ArchiveCostumeCategory {
    fn command_name() -> &'static str {
        "ArchiveCostumeCategory"
    }
}
