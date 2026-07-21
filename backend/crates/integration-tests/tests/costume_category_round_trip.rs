// SPDX-License-Identifier: AGPL-3.0
// Copyright (C2024-2026 Breakdown RS Contributors

//! Tier-4 round-trip integration tests for the season-scoped `CostumeCategory`
//! aggregate, the detail-enrichment of `CostumeDetail`, and the
//! seed-on-create saga (ADR-014 / ADR-015 / ADR-016).
//!
//! These tests drive the full live chain against ephemeral containers:
//!
//! ```text
//! EAPPEND (or saga → CommandService) → SierraDB event persisted
//!        → PostgresProcessor catches up → read via *Repository asserts the projection row
//! ```
//!
//! Requirements: Docker (or a compatible container runtime) and network access
//! to pull the SierraDB image. Excluded from `cargo-mutants` (`.mutants.toml`).

mod fixtures;

use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use breakdown_core::costume::events::{CostumeDetail, CostumeEvent};
use breakdown_core::costume::ports::CostumeRepository as _;
use breakdown_core::costume::views::CostumeView;
use breakdown_core::costume_category::events::CostumeCategoryEvent;
use breakdown_core::costume_category::ports::CostumeCategoryRepository as _;
use breakdown_core::costume_category::views::CostumeCategoryView;
use breakdown_core::shared::{
    AggregateVersion, CostumeCategoryId, LexicalSortKey, SeasonId, SeriesId,
};
use chrono::Utc;
use infra::queries::{CostumeCategoryRepositoryImpl, CostumeRepositoryImpl};
use uuid::Uuid;

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(payload)
}

async fn eappend(
    redis_client: &Arc<redis::Client>,
    stream_id: &str,
    event_type: &str,
    expected_version: &str,
    payload: &[u8],
) -> Result<()> {
    let mut conn = redis_client.get_multiplexed_tokio_connection().await?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_type)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_type} failed: {e}"))?;
    Ok(())
}

async fn await_category_found(
    repo: &CostumeCategoryRepositoryImpl,
    id: CostumeCategoryId,
) -> Result<CostumeCategoryView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id.0).await {
            Ok(view) => return Ok(view),
            Err(breakdown_core::error::DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(breakdown_core::error::DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: CostumeCategory({id:?}) not projected within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

async fn await_category_list(
    repo: &CostumeCategoryRepositoryImpl,
    season_id: SeasonId,
    min_len: usize,
) -> Result<Vec<CostumeCategoryView>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.list_by_season(season_id).await {
            Ok(views) if views.len() >= min_len => return Ok(views),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: list_by_season({season_id:?}) did not reach {min_len} rows \
                 within {PROJECTION_DEADLINE:?}"
            ),
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Wait until a category is excluded from the season list (i.e., archived).
async fn await_category_excluded_from_list(
    repo: &CostumeCategoryRepositoryImpl,
    season_id: SeasonId,
    excluded_id: Uuid,
) -> Result<()> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.list_by_season(season_id).await {
            Ok(views) if !views.iter().any(|c| c.id == excluded_id) => return Ok(()),
            Ok(_) if Instant::now() < deadline => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => bail!(
                "projection lag: category {excluded_id} still visible in list_by_season({season_id:?}) \
                 within {PROJECTION_DEADLINE:?}"
            ),
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

async fn await_costume_found(repo: &CostumeRepositoryImpl, id: Uuid) -> Result<CostumeView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(view) => return Ok(view),
            Err(breakdown_core::error::DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(breakdown_core::error::DomainError::NotFound(_)) => {
                bail!("projection lag: Costume({id}) not projected within {PROJECTION_DEADLINE:?}");
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Wait until a costume is projected with at least `min_details` detail rows.
/// This handles the eventual-consistency gap between `CostumeCreated` (0
/// details) and the subsequent `DetailAdded` events on the same stream.
async fn await_costume_with_details(
    repo: &CostumeRepositoryImpl,
    id: Uuid,
    min_details: usize,
) -> Result<CostumeView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(view) if view.details.len() >= min_details => return Ok(view),
            Ok(_) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Ok(view) => {
                bail!(
                    "projection lag: Costume({id}) has {} details, expected >= {min_details} within {PROJECTION_DEADLINE:?}",
                    view.details.len()
                );
            }
            Err(breakdown_core::error::DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(breakdown_core::error::DomainError::NotFound(_)) => {
                bail!("projection lag: Costume({id}) not projected within {PROJECTION_DEADLINE:?}");
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

// ---------------------------------------------------------------------------
// 8.1 — CostumeCategory aggregate round-trip (create → projector → projection)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn eappend_costume_category_created_round_trips_into_projection() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;

    let repo = CostumeCategoryRepositoryImpl::new(pool.clone());

    let id = CostumeCategoryId(Uuid::now_v7());
    let season_id = SeasonId::new();
    let stream_id = format!("costume_category-{id}");

    let created = CostumeCategoryEvent::CostumeCategoryCreated {
        id: id.0,
        season_id,
        name: "Oberteil".into(),
        order_key: LexicalSortKey("a".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&created)?;
    eappend(
        &redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    let view = await_category_found(&repo, id).await?;
    assert_eq!(view.id, id.0);
    assert_eq!(view.season_id, season_id);
    assert_eq!(view.name, "Oberteil");
    assert_eq!(view.order_key, LexicalSortKey("a".into()));
    assert_eq!(view.version, AggregateVersion::INITIAL);

    let list = await_category_list(&repo, season_id, 1).await?;
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, id.0);

    Ok(())
}

// ---------------------------------------------------------------------------
// 8.2 — Seed-on-create saga: SeasonCreated → per-season categories projected
// ---------------------------------------------------------------------------

#[tokio::test]
async fn season_created_seeds_exactly_five_categories_and_is_idempotent() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    // CommandService drives the saga's category creation (NEW aggregates only
    // write via ECREATE/EAPPEND — no broken ESCAN path is touched).
    let sierra_conn = redis_client.get_multiplexed_tokio_connection().await?;
    let cmd_service = kameo_es::command_service::CommandService::new(sierra_conn);

    let _cat_ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    // Spawn the saga BEFORE emitting SeasonCreated so it catches the event.
    infra::sagas::spawn_season_seeding_saga(
        pool.clone(),
        Arc::clone(&redis_client),
        cmd_service.clone(),
    )
    .await?;

    let repo = CostumeCategoryRepositoryImpl::new(pool.clone());

    let season_id = SeasonId::new();
    let stream_id = format!("season-{}", season_id.0);
    let season_created = breakdown_core::season::events::SeasonEvent::SeasonCreated {
        id: season_id.0,
        series_id: SeriesId(Uuid::now_v7()),
        number: 1,
        title: Some("Staffel 1".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&season_created)?;
    eappend(
        &redis_client,
        &stream_id,
        "SeasonCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    // The saga seeds the five default German categories for this season.
    let list = await_category_list(&repo, season_id, 5).await?;
    assert_eq!(list.len(), 5, "saga should seed exactly 5 categories");
    assert_eq!(list[0].name, "Oberteil");
    assert_eq!(list[1].name, "Unterteil");
    assert_eq!(list[2].name, "Schuhe");
    assert_eq!(list[3].name, "Jacke");
    assert_eq!(list[4].name, "Accessoires");
    // Ordered by order_key ascending.
    assert!(list[0].order_key < list[4].order_key);

    // Replay: a second SeasonCreated for the SAME season_id (different stream)
    // must NOT create a second batch of categories (idempotency guard).
    let second_stream = format!("season-{}", Uuid::now_v7());
    let season_created_again = breakdown_core::season::events::SeasonEvent::SeasonCreated {
        id: season_id.0,
        series_id: SeriesId(Uuid::now_v7()),
        number: 1,
        title: Some("Staffel 1 (replay)".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&season_created_again)?;
    eappend(
        &redis_client,
        &second_stream,
        "SeasonCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    // Give the saga a moment to (not) re-seed, then assert no duplicates.
    tokio::time::sleep(POLL_INTERVAL * 4).await;
    let list_after = repo.list_by_season(season_id).await?;
    assert_eq!(
        list_after.len(),
        5,
        "replaying SeasonCreated must not duplicate seeded categories"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 8.3 — Detail enrichment: subject + category_id + resolved category_name
// ---------------------------------------------------------------------------

#[tokio::test]
async fn costume_detail_carries_subject_category_id_and_resolved_name() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _cat_ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let cat_repo = CostumeCategoryRepositoryImpl::new(pool.clone());
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());

    // Seed a known category so the costume projector can resolve its name.
    let cat_id = CostumeCategoryId(Uuid::now_v7());
    let season_id = SeasonId::new();
    let cat_stream = format!("costume_category-{cat_id}");
    let cat_created = CostumeCategoryEvent::CostumeCategoryCreated {
        id: cat_id.0,
        season_id,
        name: "Oberteil".into(),
        order_key: LexicalSortKey("a".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&cat_created)?;
    eappend(
        &redis_client,
        &cat_stream,
        "CostumeCategoryCreated",
        "EMPTY",
        &payload,
    )
    .await?;
    await_category_found(&cat_repo, cat_id).await?;

    // Create the costume, then add a detail referencing the category.
    let costume_id = Uuid::now_v7();
    let costume_stream = format!("costume-{costume_id}");
    let costume_created = CostumeEvent::CostumeCreated {
        id: costume_id,
        character_id: None,
        notes: String::new(),
        details: vec![],
        photos: vec![],
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&costume_created)?;
    eappend(
        &redis_client,
        &costume_stream,
        "CostumeCreated",
        "EMPTY",
        &payload,
    )
    .await?;

    let detail_id = Uuid::now_v7();
    let detail_added = CostumeEvent::DetailAdded {
        id: costume_id,
        detail: CostumeDetail {
            id: detail_id,
            subject: Some("Kopf".into()),
            category_id: Some(cat_id),
            text: "Helm mit Visier".into(),
        },
        version: AggregateVersion(1),
    };
    let payload = encode_event(&detail_added)?;
    eappend(&redis_client, &costume_stream, "DetailAdded", "0", &payload).await?;

    let view = await_costume_found(&costume_repo, costume_id).await?;
    assert_eq!(
        view.details.len(),
        1,
        "costume should have exactly one detail"
    );
    let detail = &view.details[0];
    assert_eq!(detail.id, detail_id);
    assert_eq!(detail.subject.as_deref(), Some("Kopf"));
    assert_eq!(detail.category_id, Some(cat_id));
    assert_eq!(detail.category_name.as_deref(), Some("Oberteil"));
    assert_eq!(detail.text, "Helm mit Visier");

    Ok(())
}

// ---------------------------------------------------------------------------
// 8.4 — Projector idempotency under redelivery (no duplicate projection rows)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn costume_category_projector_is_idempotent_under_redelivery() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;

    let repo = CostumeCategoryRepositoryImpl::new(pool.clone());

    let id = CostumeCategoryId(Uuid::now_v7());
    let season_id = SeasonId::new();
    let stream_id = format!("costume_category-{id}");

    let created = CostumeCategoryEvent::CostumeCategoryCreated {
        id: id.0,
        season_id,
        name: "Oberteil".into(),
        order_key: LexicalSortKey("a".into()),
        version: AggregateVersion::INITIAL,
    };
    let payload = encode_event(&created)?;
    // Deliver the same event twice (simulating redelivery at the stream).
    eappend(
        &redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "EMPTY",
        &payload,
    )
    .await?;
    eappend(
        &redis_client,
        &stream_id,
        "CostumeCategoryCreated",
        "0",
        &payload,
    )
    .await?;

    let list = await_category_list(&repo, season_id, 1).await?;
    assert_eq!(list.len(), 1, "redelivery must not create a duplicate row");
    assert_eq!(list[0].id, id.0);

    let count = repo.count_for_season(season_id).await?;
    assert_eq!(
        count, 1,
        "count must reflect exactly one projected category"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 8.2 — Rename propagation: renaming a category refreshes detail category_name
// ---------------------------------------------------------------------------

async fn await_costume_detail_category_name(
    repo: &CostumeRepositoryImpl,
    costume_id: Uuid,
    detail_id: Uuid,
    expected: &str,
) -> Result<()> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(costume_id).await {
            Ok(view) => {
                if let Some(detail) = view.details.iter().find(|d| d.id == detail_id)
                    && detail.category_name.as_deref() == Some(expected)
                {
                    return Ok(());
                }
            }
            Err(breakdown_core::error::DomainError::NotFound(_)) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(breakdown_core::error::DomainError::NotFound(_)) => {
                bail!(
                    "projection lag: Costume({costume_id}) not projected within {PROJECTION_DEADLINE:?}"
                );
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
        if Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: costume detail category_name did not become {expected:?} within {PROJECTION_DEADLINE:?}"
            );
        }
    }
}

#[tokio::test]
async fn rename_category_refreshes_referencing_detail_category_name() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _cat_ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let cat_repo = CostumeCategoryRepositoryImpl::new(pool.clone());
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());

    let cat_id = CostumeCategoryId(Uuid::now_v7());
    let season_id = SeasonId::new();
    let cat_stream = format!("costume_category-{cat_id}");
    eappend(
        &redis_client,
        &cat_stream,
        "CostumeCategoryCreated",
        "EMPTY",
        &encode_event(&CostumeCategoryEvent::CostumeCategoryCreated {
            id: cat_id.0,
            season_id,
            name: "Oberteil".into(),
            order_key: LexicalSortKey("a".into()),
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    await_category_found(&cat_repo, cat_id).await?;

    let costume_id = Uuid::now_v7();
    let costume_stream = format!("costume-{costume_id}");
    eappend(
        &redis_client,
        &costume_stream,
        "CostumeCreated",
        "EMPTY",
        &encode_event(&CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    let detail_id = Uuid::now_v7();
    eappend(
        &redis_client,
        &costume_stream,
        "DetailAdded",
        "0",
        &encode_event(&CostumeEvent::DetailAdded {
            id: costume_id,
            detail: CostumeDetail {
                id: detail_id,
                subject: Some("Kopf".into()),
                category_id: Some(cat_id),
                text: "Helm".into(),
            },
            version: AggregateVersion(1),
        })?,
    )
    .await?;

    await_costume_detail_category_name(&costume_repo, costume_id, detail_id, "Oberteil").await?;

    // Rename the category; the costume_category projector must propagate the
    // new name into projection_costume_detail.
    eappend(
        &redis_client,
        &cat_stream,
        "CostumeCategoryRenamed",
        "0",
        &encode_event(&CostumeCategoryEvent::CostumeCategoryRenamed {
            id: cat_id.0,
            name: "Kopfbedeckung".into(),
            version: AggregateVersion(1),
        })?,
    )
    .await?;

    await_costume_detail_category_name(&costume_repo, costume_id, detail_id, "Kopfbedeckung")
        .await?;

    Ok(())
}

// ---------------------------------------------------------------------------
// 8.3 — Archive preserves history: detail keeps name, picker hides category
// ---------------------------------------------------------------------------

#[tokio::test]
async fn archive_category_preserves_detail_name_and_hides_from_picker() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _cat_ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let cat_repo = CostumeCategoryRepositoryImpl::new(pool.clone());
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());

    let cat_id = CostumeCategoryId(Uuid::now_v7());
    let season_id = SeasonId::new();
    let cat_stream = format!("costume_category-{cat_id}");
    eappend(
        &redis_client,
        &cat_stream,
        "CostumeCategoryCreated",
        "EMPTY",
        &encode_event(&CostumeCategoryEvent::CostumeCategoryCreated {
            id: cat_id.0,
            season_id,
            name: "Oberteil".into(),
            order_key: LexicalSortKey("a".into()),
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    await_category_found(&cat_repo, cat_id).await?;

    let costume_id = Uuid::now_v7();
    let costume_stream = format!("costume-{costume_id}");
    eappend(
        &redis_client,
        &costume_stream,
        "CostumeCreated",
        "EMPTY",
        &encode_event(&CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    let detail_id = Uuid::now_v7();
    eappend(
        &redis_client,
        &costume_stream,
        "DetailAdded",
        "0",
        &encode_event(&CostumeEvent::DetailAdded {
            id: costume_id,
            detail: CostumeDetail {
                id: detail_id,
                subject: Some("Kopf".into()),
                category_id: Some(cat_id),
                text: "Helm".into(),
            },
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    await_costume_detail_category_name(&costume_repo, costume_id, detail_id, "Oberteil").await?;

    // Archive the (referenced) category. It must NOT null the detail's name.
    eappend(
        &redis_client,
        &cat_stream,
        "CostumeCategoryArchived",
        "0",
        &encode_event(&CostumeCategoryEvent::CostumeCategoryArchived {
            id: cat_id.0,
            version: AggregateVersion(1),
        })?,
    )
    .await?;

    // Wait for the archive event to be projected (replaces static sleep)
    await_category_excluded_from_list(&cat_repo, season_id, cat_id.0).await?;
    
    // The costume detail still resolves the (now historical) category name.
    let view = costume_repo.find_by_id(costume_id).await?;
    let detail = view
        .details
        .iter()
        .find(|d| d.id == detail_id)
        .expect("detail present");
    assert_eq!(
        detail.category_name.as_deref(),
        Some("Oberteil"),
        "archiving a category must not drop referencing detail names"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 8.4 — End-to-end categorisation: costume → character → categorized detail
// ---------------------------------------------------------------------------

#[tokio::test]
async fn end_to_end_costume_categorisation_with_character() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _cat_ref = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    let _costume_ref =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    // The projection_costume table has a FK to projection_character,
    // so we need the character projector to populate it.
    let _char_ref =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;

    let cat_repo = CostumeCategoryRepositoryImpl::new(pool.clone());
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());

    // A known category so the costume detail can resolve its name.
    let cat_id = CostumeCategoryId(Uuid::now_v7());
    let season_id = SeasonId::new();
    let cat_stream = format!("costume_category-{cat_id}");
    eappend(
        &redis_client,
        &cat_stream,
        "CostumeCategoryCreated",
        "EMPTY",
        &encode_event(&CostumeCategoryEvent::CostumeCategoryCreated {
            id: cat_id.0,
            season_id,
            name: "Schuhe".into(),
            order_key: LexicalSortKey("c".into()),
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    await_category_found(&cat_repo, cat_id).await?;

    // A character for assignment.
    let char_id = Uuid::now_v7();
    let char_stream = format!("character-{char_id}");
    eappend(
        &redis_client,
        &char_stream,
        "CharacterCreated",
        "EMPTY",
        &encode_event(
            &breakdown_core::character::events::CharacterEvent::CharacterCreated {
                id: char_id,
                season_id,
                name: "Lena".into(),
                category: breakdown_core::character::category::CharacterCategory::MainCast,
                measurements: Default::default(),
                contact_info: Default::default(),
                version: AggregateVersion::INITIAL,
            },
        )?,
    )
    .await?;

    // Create the costume bound to the character, then assign explicitly, then
    // add a categorized detail.
    let costume_id = Uuid::now_v7();
    let costume_stream = format!("costume-{costume_id}");
    eappend(
        &redis_client,
        &costume_stream,
        "CostumeCreated",
        "EMPTY",
        &encode_event(&CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: Some(char_id),
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        })?,
    )
    .await?;
    eappend(
        &redis_client,
        &costume_stream,
        "CostumeAssignedToCharacter",
        "0",
        &encode_event(&CostumeEvent::CostumeAssignedToCharacter {
            id: costume_id,
            character_id: char_id,
            version: AggregateVersion(1),
        })?,
    )
    .await?;
    let detail_id = Uuid::now_v7();
    eappend(
        &redis_client,
        &costume_stream,
        "DetailAdded",
        "1",
        &encode_event(&CostumeEvent::DetailAdded {
            id: costume_id,
            detail: CostumeDetail {
                id: detail_id,
                subject: Some("Fuesse".into()),
                category_id: Some(cat_id),
                text: "Stiefel".into(),
            },
            version: AggregateVersion(2),
        })?,
    )
    .await?;

    let view = await_costume_with_details(&costume_repo, costume_id, 1).await?;
    assert_eq!(view.character_id, Some(char_id));
    let detail = &view.details[0];
    assert_eq!(detail.category_id, Some(cat_id));
    assert_eq!(detail.category_name.as_deref(), Some("Schuhe"));

    Ok(())
}
