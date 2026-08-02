// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! EventStore-Adapter (kameo_es SierraDB)

mod command_adapters;

pub use command_adapters::{
    BlockCommandsImpl, CharacterCommandsImpl, CostumeCategoryCommandsImpl, CostumeCommandsImpl,
    EpisodeCommandsImpl, MembershipCommandsImpl, PhotoCommandsImpl, SceneCommandsImpl,
    SceneShootCommandsImpl, SeasonCommandsImpl, SettingsCommandsImpl, ShootingDayCommandsImpl,
    check_nonzero_version, domain_to_stream, map_executed, map_executed_result, map_version_only,
    stream_to_domain, version_from_current, version_from_expected,
};
