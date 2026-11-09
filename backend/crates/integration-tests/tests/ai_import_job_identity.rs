// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Postgres round-trip for the AI-import job identity surface: the sanitized
//! source file name captured at upload (issue #763), the applied-episode
//! summary **derived from the durable apply mappings** (issue #864) and the
//! attempt history the jobs list carries so a degraded provider can be derived
//! without opening a job (issue #822).
//!
//! What is worth a database here is exactly what a fake cannot prove — the
//! `ON CONFLICT` behaviour of the dedup path (a duplicate re-upload must not
//! rename the existing row) and the derivation's join: scene mappings to their
//! projected scene, that scene's episode, that episode's number/title, and the
//! exclusion of reservations and schedule mappings.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportMapping, AiImportQueue,
    AppliedEpisode, DocumentKind,
};
use infra::ai::queue::PgAiImportQueue;
use uuid::Uuid;

fn make_request(user_id: &str, source_file_name: Option<&str>) -> AiImportEnqueueRequest {
    AiImportEnqueueRequest {
        id: AiImportJobId::new(),
        user_id: breakdown_core::shared::UserId::from_sub(user_id),
        document_kind: DocumentKind::Script,
        source_format: breakdown_core::ai::SourceFormat::Pdf,
        block_id: None,
        dedup_key: format!("dedup-{user_id}-{}", Uuid::now_v7()),
        document_digest: format!("digest-{}", Uuid::now_v7()),
        source_handle: format!("handle-{}", Uuid::now_v7()),
        source_file_name: source_file_name.map(str::to_owned),
        target: None,
    }
}

#[tokio::test]
async fn source_file_name_round_trips() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_request("user-identity", Some("Erlösung Skript.pdf"));
    let id = request.id;
    queue.enqueue(request).await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.source_file_name.as_deref(), Some("Erlösung Skript.pdf"));
    Ok(())
}

#[tokio::test]
async fn an_unnamed_upload_stays_null() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_request("user-identity-null", None);
    let id = request.id;
    queue.enqueue(request).await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.source_file_name, None,
        "an upload without a name must not invent one"
    );
    Ok(())
}

/// A duplicate re-upload is answered with the existing job — and that row keeps
/// the name it was created with. `ON CONFLICT` echoes only `dedup_key`, so the
/// identity the user already recognises cannot be rewritten by a second pick.
#[tokio::test]
async fn a_duplicate_upload_does_not_rename_the_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let mut first = make_request("user-identity-dedup", Some("Original.pdf"));
    let dedup_key = first.dedup_key.clone();
    let first_id = first.id;
    assert_eq!(
        queue.enqueue(first.clone()).await?,
        AiImportEnqueueResult::Enqueued(first_id)
    );

    // Same dedup key (same user, kind, format and digest) — a second pick of
    // the same bytes under a different name.
    first.id = AiImportJobId::new();
    first.dedup_key = dedup_key;
    first.source_file_name = Some("Umbenannt.pdf".to_owned());
    assert_eq!(
        queue.enqueue(first).await?,
        AiImportEnqueueResult::Existing(first_id)
    );

    let job = queue.get(first_id).await?.expect("job exists");
    assert_eq!(job.source_file_name.as_deref(), Some("Original.pdf"));
    Ok(())
}

/// Insert one `projection_scene` row: the scene an applied draft row became.
///
/// The tiny column set is deliberate — the derivation only needs the scene's
/// identity and its episode.
async fn insert_scene(pool: &sqlx::PgPool, scene_id: Uuid, episode_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_scene
            (id, episode_id, scene_number, location, mood, is_schedule_set,
             version, updated_at)
        VALUES ($1, $2, 1, 'Studio', 'Neutral', false, 1, now())
        "#,
    )
    .bind(scene_id)
    .bind(episode_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Insert one `projection_episode` row — the label source of a derived entry.
async fn insert_episode(
    pool: &sqlx::PgPool,
    episode_id: Uuid,
    number: i32,
    name: Option<&str>,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO projection_episode
            (id, block_id, project_id, number, name, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, 1, now())
        "#,
    )
    .bind(episode_id)
    .bind(Uuid::now_v7())
    .bind(Uuid::now_v7())
    .bind(number)
    .bind(name)
    .execute(pool)
    .await?;
    Ok(())
}

/// Insert one idempotency mapping row, exactly as the apply worker confirms it.
/// `aggregate_version = 0` is a *reservation* (the id is claimed, no command
/// appended yet) — see [`AiImportMapping::RESERVED_VERSION`].
async fn insert_mapping(
    pool: &sqlx::PgPool,
    job_id: AiImportJobId,
    draft_ref: &str,
    aggregate_kind: &str,
    aggregate_id: Uuid,
    aggregate_version: i64,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO ai_import.projection_ai_import_mapping
            (preview_id, draft_ref, aggregate_kind, ordinal, aggregate_id,
             aggregate_version)
        VALUES ($1, $2, $3, 0, $4, $5)
        "#,
    )
    .bind(job_id.as_uuid())
    .bind(draft_ref)
    .bind(aggregate_kind)
    .bind(aggregate_id)
    .bind(aggregate_version)
    .execute(pool)
    .await?;
    Ok(())
}

/// The applied-episode summary is **derived from the durable apply mappings**
/// (issue #864), so it survives an apply whose caller disconnected: nothing has
/// to be written after the run for the job to name its target.
///
/// This test seeds exactly what a committed apply leaves behind — a confirmed
/// `scene` mapping per applied draft row plus the projected scene and episode —
/// and reads the job back. No summary write happens anywhere in it, which is the
/// point: the old best-effort column could not be asserted this way, because
/// "rows committed, summary missing" was a reachable state.
#[tokio::test]
async fn applied_episodes_are_derived_from_the_apply_mappings() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let request = make_request("user-identity-derived", None);
    let id = request.id;
    queue.enqueue(request).await?;

    // Nothing applied yet: an empty list, not a fabricated entry.
    let fresh = queue.get(id).await?.expect("job exists");
    assert!(
        fresh.applied_episodes.is_empty(),
        "a job no apply has run for names no target"
    );

    // Episode 299 "Erlösung" received two rows; episode 300 is projected but
    // UNTITLED; episode 301 is not projected at all (projector lag, or a target
    // whose episode row this deployment never saw) and received one row each.
    let episode_299 = Uuid::now_v7();
    let episode_300 = Uuid::now_v7();
    let episode_301 = Uuid::now_v7();
    insert_episode(&pool, episode_299, 299, Some("Erlösung")).await?;
    insert_episode(&pool, episode_300, 300, None).await?;
    for (index, draft_ref) in ["scene-0", "scene-1"].iter().enumerate() {
        let scene_id = Uuid::now_v7();
        insert_scene(&pool, scene_id, episode_299).await?;
        insert_mapping(&pool, id, draft_ref, "scene", scene_id, 1 + index as i64).await?;
    }
    let scene_300 = Uuid::now_v7();
    insert_scene(&pool, scene_300, episode_300).await?;
    insert_mapping(&pool, id, "scene-2", "scene", scene_300, 1).await?;
    // A mapped scene whose episode has NO `projection_episode` row: the entry
    // must still exist (a LEFT join, not an inner one) with honest-absent
    // labels — dropping it would make a real applied row invisible.
    let scene_301 = Uuid::now_v7();
    insert_scene(&pool, scene_301, episode_301).await?;
    insert_mapping(&pool, id, "scene-3", "scene", scene_301, 1).await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.applied_episodes,
        vec![
            AppliedEpisode {
                id: episode_299,
                number: Some(299),
                name: Some("Erlösung".to_owned()),
                applied_count: 2,
            },
            AppliedEpisode {
                id: episode_300,
                number: Some(300),
                name: None,
                applied_count: 1,
            },
            AppliedEpisode {
                id: episode_301,
                number: None,
                name: None,
                applied_count: 1,
            },
        ],
        "one entry per episode, ordered by number (unlabelled last), labelled \
         from the projection — an unprojected episode keeps its row"
    );
    Ok(())
}

/// Not every mapping is applied work, and not every apply names a target.
///
/// * a **reserved** scene mapping (an id claimed before the command appended)
///   has no projected scene, so the join drops it — a reservation is not a row;
/// * a **schedule** apply writes only `scene_shoot`/`shooting_day` mappings, so
///   it derives an empty list instead of an invented one (the #763 decision now
///   falls out of the derivation rather than being a special case).
#[tokio::test]
async fn reservations_and_schedule_mappings_derive_no_target() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let request = make_request("user-identity-reserved", None);
    let id = request.id;
    queue.enqueue(request).await?;

    // A crashed attempt claimed an id and never appended: `RESERVED_VERSION`.
    insert_mapping(
        &pool,
        id,
        "scene-0",
        "scene",
        Uuid::now_v7(),
        i64::try_from(AiImportMapping::RESERVED_VERSION.0)?,
    )
    .await?;
    // A schedule merge: scene-shoot and shooting-day mappings only.
    insert_mapping(&pool, id, "day-0", "scene_shoot", Uuid::now_v7(), 1).await?;
    insert_mapping(&pool, id, "day-1", "shooting_day", Uuid::now_v7(), 1).await?;

    let job = queue.get(id).await?.expect("job exists");
    assert!(
        job.applied_episodes.is_empty(),
        "a reservation is not applied work and a schedule merge names no episode: {:?}",
        job.applied_episodes
    );
    Ok(())
}

/// The jobs **list** derives the same summary as the single-job read, in one
/// batch query per page (issue #864) — the list is where a user actually meets
/// the target name, so a divergence between the two reads would be the defect.
#[tokio::test]
async fn the_jobs_list_derives_the_same_summary() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let user = "user-identity-list";
    let applied = make_request(user, None);
    let applied_id = applied.id;
    queue.enqueue(applied).await?;
    let untouched = make_request(user, None);
    let untouched_id = untouched.id;
    queue.enqueue(untouched).await?;

    let episode = Uuid::now_v7();
    insert_episode(&pool, episode, 299, Some("Erlösung")).await?;
    let scene = Uuid::now_v7();
    insert_scene(&pool, scene, episode).await?;
    insert_mapping(&pool, applied_id, "scene-0", "scene", scene, 1).await?;

    let jobs = queue
        .list_for_user(&breakdown_core::shared::UserId::from_sub(user), 10, 0)
        .await?;
    let listed = |wanted: AiImportJobId| {
        jobs.iter()
            .find(|job| job.id == wanted)
            .cloned()
            .expect("the enqueued job is listed")
    };
    assert_eq!(
        listed(applied_id).applied_episodes,
        vec![AppliedEpisode {
            id: episode,
            number: Some(299),
            name: Some("Erlösung".to_owned()),
            applied_count: 1,
        }]
    );
    assert!(
        listed(untouched_id).applied_episodes.is_empty(),
        "a job that was never applied keeps answering 'no target'"
    );
    Ok(())
}

/// The jobs **list** carries the attempt history the degraded-provider
/// aggregate is derived from (issue #822).
///
/// The stored codes are what a client is allowed to branch on (the free-form
/// `error_summary` never is), and the list read must publish the SAME codes the
/// single-job read publishes — otherwise the compact row and the status screen
/// could disagree about whether the provider is degraded. This asserts the
/// provider-attributed code and the unattributed one side by side, because the
/// whole point of the new code is that they are distinguishable.
#[tokio::test]
async fn the_jobs_list_carries_the_attempt_codes() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let user = "user-identity-attempts";
    let provider = make_request(user, None);
    let provider_id = provider.id;
    queue.enqueue(provider).await?;

    // Two consecutive provider-attributed attempts on ONE job — the run the
    // client aggregates — recorded through the same mark_failed path the
    // worker uses. The backoff is made due between the two attempts because
    // this test asserts the READ, not the schedule.
    for _ in 0..2 {
        let claimed = queue.claim_next("worker-1").await?.expect("claimable");
        assert_eq!(claimed.id, provider_id, "the provider job is the only one");
        queue
            .mark_failed(
                provider_id,
                "worker-1",
                "service unavailable: LLM provider returned HTTP 503 Service Unavailable",
                Some("ai-import.llm-provider-unavailable"),
                true,
            )
            .await?;
        sqlx::query("UPDATE ai_import.ai_import_job SET next_attempt_at = now() WHERE id = $1")
            .bind(provider_id.as_uuid())
            .execute(&pool)
            .await?;
    }
    // Park the provider job so the next claim can only pick the new one.
    sqlx::query(
        "UPDATE ai_import.ai_import_job \
         SET next_attempt_at = now() + interval '1 hour' WHERE id = $1",
    )
    .bind(provider_id.as_uuid())
    .execute(&pool)
    .await?;

    // The OTHER job fails on a non-provider dependency and keeps the generic
    // code — the attribution must not swallow it.
    let storage = make_request(user, None);
    let storage_id = storage.id;
    queue.enqueue(storage).await?;
    let claimed = queue.claim_next("worker-1").await?.expect("claimable");
    assert_eq!(claimed.id, storage_id);
    queue
        .mark_failed(
            storage_id,
            "worker-1",
            "service unavailable: AI mapping database error",
            Some("domain.service-unavailable"),
            true,
        )
        .await?;

    let jobs = queue
        .list_for_user(&breakdown_core::shared::UserId::from_sub(user), 10, 0)
        .await?;
    let listed = |wanted: AiImportJobId| {
        jobs.iter()
            .find(|job| job.id == wanted)
            .cloned()
            .expect("the enqueued job is listed")
    };
    let provider_codes: Vec<Option<String>> = listed(provider_id)
        .attempts
        .iter()
        .map(|attempt| attempt.code.clone())
        .collect();
    assert_eq!(
        provider_codes,
        vec![
            Some("ai-import.llm-provider-unavailable".to_owned()),
            Some("ai-import.llm-provider-unavailable".to_owned()),
        ],
        "the list read must carry every attempt of the provider run, newest first"
    );
    assert_eq!(
        listed(storage_id)
            .attempts
            .first()
            .and_then(|attempt| attempt.code.as_deref()),
        Some("domain.service-unavailable"),
        "a non-provider dependency keeps the generic code"
    );
    Ok(())
}
