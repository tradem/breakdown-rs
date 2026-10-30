// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Closed keep/reset classification of every aggregate category (issue #770).
//!
//! The reset tooling must never guess: every aggregate category in the
//! workspace is classified here as **keep** (configuration that survives a
//! reset) or **reset** (business data). The enforcement is two-layered, and
//! together the two layers give the "a new aggregate can never silently
//! default into keep" property the issue demands:
//!
//! 1. [`AggregateCategory::class`] is an **exhaustive** `match` over the
//!    variant list — adding a variant without classifying it does not compile.
//! 2. [`tests::every_entity_category_in_the_workspace_is_classified`] scans the
//!    workspace sources for `Entity::category()` literals, so a **new
//!    aggregate** (a new category string) fails the suite until its variant is
//!    added — which then trips layer 1 until it is classified.

/// What a data reset does with an aggregate category.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AggregateClass {
    /// Configuration — exported, wiped and replayed, or left untouched.
    Keep,
    /// Business data — deleted (level `imports`) or wiped (level `business`).
    Reset,
}

impl AggregateClass {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Keep => "keep",
            Self::Reset => "reset",
        }
    }
}

/// Every aggregate category in the workspace.
///
/// Ordered keep-first, then by the production hierarchy, so the rendered plan
/// reads top-down.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AggregateCategory {
    // ── configuration (keep) ────────────────────────────────────────────────
    AiConfig,
    Settings,
    Membership,
    // ── business data (reset) ───────────────────────────────────────────────
    Season,
    Block,
    Episode,
    Scene,
    SceneShoot,
    ShootingDay,
    Character,
    Piece,
    Outfit,
    CostumeCategory,
    Photo,
    /// ADR-036 reservation streams (`reservation-*`): bookkeeping, never
    /// business truth. Reset with the business data; the level-`imports`
    /// delete path releases individual claims instead of wiping them.
    Reservation,
}

impl AggregateCategory {
    /// Every category, in plan order.
    pub const ALL: [Self; 15] = [
        Self::AiConfig,
        Self::Settings,
        Self::Membership,
        Self::Season,
        Self::Block,
        Self::Episode,
        Self::Scene,
        Self::SceneShoot,
        Self::ShootingDay,
        Self::Character,
        Self::Piece,
        Self::Outfit,
        Self::CostumeCategory,
        Self::Photo,
        Self::Reservation,
    ];

    /// The category string the aggregate declares in its `Entity` impl.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::AiConfig => "ai_config",
            Self::Settings => "settings",
            Self::Membership => "membership",
            Self::Season => "season",
            Self::Block => "block",
            Self::Episode => "episode",
            Self::Scene => "scene",
            Self::SceneShoot => "scene_shoot",
            Self::ShootingDay => "shooting_day",
            Self::Character => "character",
            Self::Piece => "piece",
            Self::Outfit => "outfit",
            Self::CostumeCategory => "costume_category",
            Self::Photo => "photo",
            Self::Reservation => "reservation",
        }
    }

    /// Keep or reset — the closed match (issue #770).
    ///
    /// A new variant does not compile until it lands in one of these two arms;
    /// there is deliberately no `_ =>` fallback, so no category can ever
    /// inherit "keep" by accident.
    pub const fn class(self) -> AggregateClass {
        match self {
            Self::AiConfig | Self::Settings | Self::Membership => AggregateClass::Keep,
            Self::Season
            | Self::Block
            | Self::Episode
            | Self::Scene
            | Self::SceneShoot
            | Self::ShootingDay
            | Self::Character
            | Self::Piece
            | Self::Outfit
            | Self::CostumeCategory
            | Self::Photo
            | Self::Reservation => AggregateClass::Reset,
        }
    }

    /// The projection table carrying this category's read model.
    pub const fn projection_table(self) -> &'static str {
        match self {
            Self::AiConfig => "ai_import.projection_ai_config",
            Self::Settings => "projection_settings",
            Self::Membership => "projection_membership",
            Self::Season => "projection_season",
            Self::Block => "projection_block",
            Self::Episode => "projection_episode",
            Self::Scene => "projection_scene",
            Self::SceneShoot => "projection_scene_shoot",
            Self::ShootingDay => "projection_shooting_day",
            Self::Character => "projection_character",
            Self::Piece => "projection_piece",
            Self::Outfit => "projection_outfit",
            Self::CostumeCategory => "projection_costume_category",
            Self::Photo => "projection_photo",
            Self::Reservation => "projection_number_reservation",
        }
    }

    /// Static `count(*)` statement for this category's projection table.
    ///
    /// A literal per variant, never a formatted string: the no-string-
    /// interpolated-SQL rule (AGENTS.md §3) forbids building statements from
    /// values, and this match is exhaustive, so a new category cannot be
    /// counted by accident.
    pub const fn count_sql(self) -> &'static str {
        match self {
            Self::AiConfig => "SELECT count(*) FROM ai_import.projection_ai_config",
            Self::Settings => "SELECT count(*) FROM projection_settings",
            Self::Membership => "SELECT count(*) FROM projection_membership",
            Self::Season => "SELECT count(*) FROM projection_season",
            Self::Block => "SELECT count(*) FROM projection_block",
            Self::Episode => "SELECT count(*) FROM projection_episode",
            Self::Scene => "SELECT count(*) FROM projection_scene",
            Self::SceneShoot => "SELECT count(*) FROM projection_scene_shoot",
            Self::ShootingDay => "SELECT count(*) FROM projection_shooting_day",
            Self::Character => "SELECT count(*) FROM projection_character",
            Self::Piece => "SELECT count(*) FROM projection_piece",
            Self::Outfit => "SELECT count(*) FROM projection_outfit",
            Self::CostumeCategory => "SELECT count(*) FROM projection_costume_category",
            Self::Photo => "SELECT count(*) FROM projection_photo",
            Self::Reservation => "SELECT count(*) FROM projection_number_reservation",
        }
    }

    /// Static `DELETE`/`TRUNCATE`-equivalent statement used by the business
    /// wipe for this category's projection table.
    ///
    /// `projection_*` child tables hang off the parent rows with
    /// `ON DELETE CASCADE`, so the category table is the only statement needed.
    pub const fn truncate_sql(self) -> &'static str {
        match self {
            Self::AiConfig => "DELETE FROM ai_import.projection_ai_config",
            Self::Settings => "DELETE FROM projection_settings",
            Self::Membership => "DELETE FROM projection_membership",
            Self::Season => "DELETE FROM projection_season",
            Self::Block => "DELETE FROM projection_block",
            Self::Episode => "DELETE FROM projection_episode",
            Self::Scene => "DELETE FROM projection_scene",
            Self::SceneShoot => "DELETE FROM projection_scene_shoot",
            Self::ShootingDay => "DELETE FROM projection_shooting_day",
            Self::Character => "DELETE FROM projection_character",
            Self::Piece => "DELETE FROM projection_piece",
            Self::Outfit => "DELETE FROM projection_outfit",
            Self::CostumeCategory => "DELETE FROM projection_costume_category",
            Self::Photo => "DELETE FROM projection_photo",
            Self::Reservation => "DELETE FROM projection_number_reservation",
        }
    }

    /// Classifies a category string. `None` means "not in the registry", which
    /// the tooling treats as a hard error — never as "keep".
    pub fn classify(category: &str) -> Option<AggregateClass> {
        Self::ALL
            .iter()
            .find(|candidate| candidate.as_str() == category)
            .map(|candidate| candidate.class())
    }

    /// Looks a category up by its string form.
    pub fn lookup(category: &str) -> Option<Self> {
        Self::ALL
            .iter()
            .copied()
            .find(|candidate| candidate.as_str() == category)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kameo_es::Entity;

    use breakdown_core::ai::aggregate::AiConfig;
    use breakdown_core::block::aggregate::BlockAggregate;
    use breakdown_core::character::aggregate::CharacterAggregate;
    use breakdown_core::costume_category::aggregate::CostumeCategoryAggregate;
    use breakdown_core::episode::aggregate::EpisodeAggregate;
    use breakdown_core::membership::aggregate::BlockMembership;
    use breakdown_core::outfit::aggregate::OutfitAggregate;
    use breakdown_core::photo::aggregate::PhotoAggregate;
    use breakdown_core::piece::aggregate::PieceAggregate;
    use breakdown_core::scene::aggregate::SceneAggregate;
    use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
    use breakdown_core::season::aggregate::SeasonAggregate;
    use breakdown_core::settings::aggregate::SettingsAggregate;
    use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;

    /// The registry string must be the string the aggregate actually declares —
    /// otherwise the tooling would classify a category nobody writes.
    #[test]
    fn registry_strings_match_the_aggregates() {
        let declared = [
            <AiConfig as Entity>::category(),
            <SettingsAggregate as Entity>::category(),
            <BlockMembership as Entity>::category(),
            <SeasonAggregate as Entity>::category(),
            <BlockAggregate as Entity>::category(),
            <EpisodeAggregate as Entity>::category(),
            <SceneAggregate as Entity>::category(),
            <SceneShootAggregate as Entity>::category(),
            <ShootingDayAggregate as Entity>::category(),
            <CharacterAggregate as Entity>::category(),
            <PieceAggregate as Entity>::category(),
            <OutfitAggregate as Entity>::category(),
            <CostumeCategoryAggregate as Entity>::category(),
            <PhotoAggregate as Entity>::category(),
            crate::reservations::event::RESERVATION_CATEGORY,
        ];
        let registered: Vec<&str> = AggregateCategory::ALL.iter().map(|c| c.as_str()).collect();
        assert_eq!(declared.len(), registered.len());
        for category in declared {
            assert!(
                registered.contains(&category),
                "aggregate category {category:?} is not in the reset classification registry"
            );
        }
    }

    /// Every variant is reachable by its string form (no dead registry entry).
    #[test]
    fn every_variant_round_trips() {
        for category in AggregateCategory::ALL {
            assert_eq!(AggregateCategory::lookup(category.as_str()), Some(category));
            assert_eq!(
                AggregateCategory::classify(category.as_str()),
                Some(category.class())
            );
        }
    }

    /// Unknown categories are never silently kept.
    #[test]
    fn unknown_category_is_not_classified() {
        assert_eq!(AggregateCategory::classify("not_a_category"), None);
        assert_eq!(AggregateCategory::lookup(""), None);
    }

    /// The keep-list is exactly the configuration triple (issue #770).
    #[test]
    fn keep_list_is_the_configuration_triple() {
        let keep: Vec<&str> = AggregateCategory::ALL
            .iter()
            .filter(|c| c.class() == AggregateClass::Keep)
            .map(|c| c.as_str())
            .collect();
        assert_eq!(keep, vec!["ai_config", "settings", "membership"]);
    }

    /// Layer 2 of the enforcement: a **new aggregate** anywhere in the
    /// workspace fails this test until its category is registered above.
    #[test]
    fn every_entity_category_in_the_workspace_is_classified() {
        let backend = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("crates/infra has a parent")
            .parent()
            .expect("crates has a parent")
            .to_path_buf();
        let mut sources = Vec::new();
        collect_rust_sources(&backend.join("crates"), &mut sources);
        assert!(
            sources.len() > 100,
            "expected the workspace sources under {}, found {}",
            backend.join("crates").display(),
            sources.len()
        );

        let mut declared = Vec::new();
        for path in sources {
            let Ok(text) = std::fs::read_to_string(&path) else {
                continue;
            };
            for category in declared_categories(&text) {
                declared.push((category.to_string(), path.clone()));
            }
        }
        assert!(
            !declared.is_empty(),
            "no `fn category()` impls found — the scan anchor went stale"
        );
        for (category, path) in declared {
            assert!(
                AggregateCategory::lookup(&category).is_some(),
                "{} declares aggregate category {category:?}, which is missing from \
                 `dev_reset::classification::AggregateCategory` — classify it as keep or reset \
                 before shipping (issue #770)",
                path.display()
            );
        }
    }

    /// Extracts the string literal returned by every `fn category()` impl.
    fn declared_categories(text: &str) -> Vec<&str> {
        const ANCHOR: &str = "fn category() -> &'static str {";
        let mut found = Vec::new();
        let mut rest = text;
        while let Some(index) = rest.find(ANCHOR) {
            rest = &rest[index + ANCHOR.len()..];
            let window = &rest[..rest.len().min(200)];
            if let Some(start) = window.find('"')
                && let Some(end) = window[start + 1..].find('"')
            {
                found.push(&window[start + 1..start + 1 + end]);
            }
        }
        found
    }

    fn collect_rust_sources(dir: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_rust_sources(&path, out);
            } else if path.extension().and_then(|ext| ext.to_str()) == Some("rs") {
                out.push(path);
            }
        }
    }
}
