// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use breakdown_core::costume_category::commands::{
    ArchiveCostumeCategory, CreateCostumeCategory, ReorderCostumeCategory, RenameCostumeCategory,
};
use breakdown_core::costume_category::error::CostumeCategoryError;
use breakdown_core::costume_category::ports::{CostumeCategoryCommands, CostumeCategoryRepository};
use breakdown_core::error::DomainError;
use breakdown_core::shared::{AggregateVersion, SeasonId};
use infra::sagas::season_seeding::seed_season;
use std::sync::Arc;
use std::sync::Mutex;

/// Fake repository that tracks how many categories exist per season.
#[derive(Default)]
struct FakeCategoryRepo {
    count: Arc<Mutex<i64>>,
}

#[allow(async_fn_in_trait)]
impl CostumeCategoryRepository for FakeCategoryRepo {
    async fn count_for_season(&self, _season_id: SeasonId) -> Result<i64, DomainError> {
        Ok(*self.count.lock().unwrap())
    }
    async fn list_by_season(&self, _season_id: SeasonId) -> Result<Vec<breakdown_core::costume_category::views::CostumeCategoryView>, DomainError> {
        Ok(Vec::new())
    }
    async fn find_by_id(&self, _id: uuid::Uuid) -> Result<breakdown_core::costume_category::views::CostumeCategoryView, DomainError> {
        Err(DomainError::NotFound("nope".into()))
    }
}

/// Fake commands that record CreateCostumeCategory calls.
#[derive(Default)]
struct FakeCategoryCommands {
    created: Arc<Mutex<Vec<CreateCostumeCategory>>>,
}

#[allow(async_fn_in_trait)]
impl CostumeCategoryCommands for FakeCategoryCommands {
    async fn create(
        &self,
        cmd: CreateCostumeCategory,
    ) -> Result<(uuid::Uuid, AggregateVersion), DomainError> {
        self.created.lock().unwrap().push(cmd);
        Ok((uuid::Uuid::now_v7(), AggregateVersion::INITIAL))
    }
    async fn rename(
        &self,
        _cmd: RenameCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
    async fn reorder(
        &self,
        _cmd: ReorderCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
    async fn archive(
        &self,
        _cmd: ArchiveCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
}

#[tokio::test]
async fn test_seed_creates_one_per_entry() {
    let repo = FakeCategoryRepo::default();
    let cmds = FakeCategoryCommands::default();
    let seed = vec!["Oberteil".into(), "Schuhe".into()];
    seed_season(&cmds, &repo, &seed, SeasonId::new())
        .await
        .unwrap();
    assert_eq!(cmds.created.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn test_replayed_season_does_not_double_seed() {
    let repo = FakeCategoryRepo {
        count: Arc::new(Mutex::new(0)),
    };
    let cmds = FakeCategoryCommands::default();
    let seed = vec!["Oberteil".into(), "Schuhe".into()];
    let sid = SeasonId::new();

    seed_season(&cmds, &repo, &seed, sid).await.unwrap();
    assert_eq!(cmds.created.lock().unwrap().len(), 2);

    // Simulate the season now having categories: bump the count guard.
    *repo.count.lock().unwrap() = 2;
    seed_season(&cmds, &repo, &seed, sid).await.unwrap();

    // Still only the original two — replay produced zero new commands.
    assert_eq!(cmds.created.lock().unwrap().len(), 2);
}

#[test]
fn test_embedded_seed_toml_parses_to_five_names() {
    let content = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../config/default_costume_categories.toml"
    ));
    let cfg: infra::sagas::season_seeding::DefaultCostumeCategoriesToml =
        toml::from_str(content).expect("embedded seed TOML must parse");
    assert_eq!(cfg.names.len(), 5);
    assert_eq!(cfg.names[0], "Oberteil");
    assert_eq!(cfg.names[4], "Accessoires");
}
