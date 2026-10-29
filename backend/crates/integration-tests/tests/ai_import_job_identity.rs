// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Postgres round-trip for the AI-import job identity columns (issue #763):
//! the sanitized source file name captured at upload and the applied-episode
//! summary written by a successful apply.
//!
//! What is worth a database here is exactly what the fake cannot prove — the
//! `ON CONFLICT` behaviour of the dedup path (a duplicate re-upload must not
//! rename the existing row) and the JSONB decode of an empty vs. a populated
//! summary.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue, AppliedEpisode,
    DocumentKind,
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

/// The summary MERGES (issue #763 review): a later apply adds the episodes it
/// dispatched and restates a known one in place, and an empty list is a no-op —
/// so a re-apply that found everything already applied cannot erase the earlier
/// attribution.
#[tokio::test]
async fn applied_episodes_merge_instead_of_replacing() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_request("user-identity-merge", None);
    let id = request.id;
    queue.enqueue(request).await?;

    let episode_a = Uuid::now_v7();
    let episode_b = Uuid::now_v7();
    let a = AppliedEpisode {
        id: episode_a,
        number: Some(299),
        name: Some("Erlösung".to_owned()),
        applied_count: 57,
    };
    queue
        .record_applied_episodes(id, std::slice::from_ref(&a))
        .await?;

    // A second apply dispatched rows into ANOTHER episode: appended, kept.
    let b = AppliedEpisode {
        id: episode_b,
        number: Some(301),
        name: None,
        applied_count: 4,
    };
    queue
        .record_applied_episodes(id, std::slice::from_ref(&b))
        .await?;
    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.applied_episodes, vec![a.clone(), b.clone()]);

    // A later apply reports only the rows IT dispatched: the count is
    // ACCUMULATED on the stored entry (57 + 3 = 60) and the position is kept,
    // instead of replacing 57 with 3 or duplicating the episode.
    let later = AppliedEpisode {
        applied_count: 3,
        ..a.clone()
    };
    queue
        .record_applied_episodes(id, std::slice::from_ref(&later))
        .await?;
    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.applied_episodes,
        vec![
            AppliedEpisode {
                applied_count: 60,
                ..a.clone()
            },
            b.clone()
        ]
    );

    // A retry that dispatched nothing must not clear the summary.
    queue.record_applied_episodes(id, &[]).await?;
    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.applied_episodes
            .first()
            .map(|entry| entry.applied_count),
        Some(60),
        "an empty report must be a no-op, not a wipe"
    );
    assert_eq!(job.applied_episodes.len(), 2);
    Ok(())
}

#[tokio::test]
async fn applied_episodes_round_trip() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_request("user-identity-applied", None);
    let id = request.id;
    queue.enqueue(request).await?;

    // Nothing is applied yet: an empty list, not a fabricated entry.
    let fresh = queue.get(id).await?.expect("job exists");
    assert!(fresh.applied_episodes.is_empty());

    let summary = vec![
        AppliedEpisode {
            id: Uuid::now_v7(),
            number: Some(299),
            name: Some("Erlösung".to_owned()),
            applied_count: 57,
        },
        AppliedEpisode {
            id: Uuid::now_v7(),
            number: Some(300),
            name: None,
            applied_count: 4,
        },
    ];
    queue.record_applied_episodes(id, &summary).await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.applied_episodes, summary);
    Ok(())
}
