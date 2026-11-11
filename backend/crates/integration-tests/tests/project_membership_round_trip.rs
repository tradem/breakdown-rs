// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-3 / Tier-4 tests for the **project-scoped** membership scope
//! (`openspec/changes/project-scoped-membership`, tasks 2.2–2.5 and 3.3).
//!
//! The block scope (`projection_membership`) joins `projection_block`, so a
//! season without blocks has no roles at all. This file pins the additive second
//! scope against real SQL: the projector's redelivery idempotency, the
//! bootstrap on season creation, the effective-resolution precedence
//! (block first, then project, fail closed) and the deliberate *absence* of the
//! project fallback on the report-archive predicate.
//!
//! Like `membership_round_trip.rs` these are black-box tier-3/4 tests: command
//! → SierraDB → projector → PostgreSQL projection → read-back (ADR-016).

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::block::commands::CreateBlock;
use breakdown_core::block::ports::BlockCommands;
use breakdown_core::membership::commands::BootstrapOwner;
use breakdown_core::membership::ports::MembershipCommands;
use breakdown_core::membership::{MembershipRepository, Role};
use breakdown_core::project_membership::commands::GrantProjectRole;
use breakdown_core::project_membership::events::ProjectMembershipEvent;
use breakdown_core::season::commands::CreateSeason;
use breakdown_core::season::ports::SeasonCommands;
use breakdown_core::shared::{BlockId, ProjectId, SeasonId, UserId};
use infra::event_store::{BlockCommandsImpl, MembershipCommandsImpl, SeasonCommandsImpl};
use infra::projectors::{
    spawn_block_projector, spawn_membership_projector, spawn_project_membership_projector,
    spawn_season_projector,
};
use infra::queries::MembershipRepositoryImpl;
use kameo_es::command_service::CommandService;
use redis::Client as RedisClient;
use sqlx::PgPool;
use testcontainers::ContainerAsync;
use testcontainers_modules::postgres::Postgres;
use uuid::Uuid;

/// Bounded-retry window for the projectors to catch up (ADR-015 eventual
/// consistency). Mirrors the sibling membership tests.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// The projected row of `(project_id, user_id)` as `(role, state)`, read with
/// raw SQL: the row itself is what task 2.2 has to get right, and there is no
/// port method that returns a revoked row.
async fn projected_grant(
    pool: &PgPool,
    project_id: ProjectId,
    user_id: &UserId,
) -> Result<Option<(String, String)>> {
    sqlx::query_as::<_, (String, String)>(
        "SELECT role, state FROM projection_project_membership \
         WHERE project_id = $1 AND user_id = $2",
    )
    .bind(project_id.0)
    .bind(user_id.as_str())
    .fetch_optional(pool)
    .await
    .map_err(|e| anyhow!("reading projection_project_membership failed: {e}"))
}

/// Wait until the projected `(role, state)` pair for `(project_id, user_id)`
/// reaches `expected` (projector catch-up, ADR-015).
async fn await_projected_grant(
    pool: &PgPool,
    project_id: ProjectId,
    user_id: &UserId,
    expected: (&str, &str),
) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let row = projected_grant(pool, project_id, user_id).await?;
        if let Some((role, state)) = row.clone()
            && role == expected.0
            && state == expected.1
        {
            return Ok(());
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: project grant ({project_id:?}, {user_id:?}) = {row:?}, \
                 expected {expected:?} within {PROJECTION_DEADLINE:?}"
            );
        }
    }
}

/// Wait until `projection_project_membership` holds exactly `expected` rows for
/// the project — the row COUNT is the idempotency assertion (a duplicated
/// bootstrap event must not add a second row).
async fn await_project_grant_count(
    pool: &PgPool,
    project_id: ProjectId,
    expected: i64,
) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let count: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM projection_project_membership WHERE project_id = $1",
        )
        .bind(project_id.0)
        .fetch_one(pool)
        .await
        .map_err(|e| anyhow!("counting project grants failed: {e}"))?;
        if count == expected {
            return Ok(());
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: {count} project grant rows for {project_id:?}, \
                 expected {expected} within {PROJECTION_DEADLINE:?}"
            );
        }
    }
}

/// Wait until the season projection row exists — the project fallback joins it
/// to resolve `season.project_id`.
async fn await_season_projected(pool: &PgPool, season_id: Uuid) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let present: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM projection_season WHERE id = $1")
                .bind(season_id)
                .fetch_optional(pool)
                .await
                .map_err(|e| anyhow!("reading projection_season failed: {e}"))?;
        if present.is_some() {
            return Ok(());
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: Season({season_id}) not projected within {PROJECTION_DEADLINE:?}"
            );
        }
    }
}

/// Wait until `projection_block` carries `block_id` — the block scope joins it.
async fn await_block_projected(pool: &PgPool, block_id: Uuid) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let present: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM projection_block WHERE id = $1")
                .bind(block_id)
                .fetch_optional(pool)
                .await
                .map_err(|e| anyhow!("reading projection_block failed: {e}"))?;
        if present.is_some() {
            return Ok(());
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!("projection lag: Block({block_id}) not projected within {PROJECTION_DEADLINE:?}");
        }
    }
}

/// Wait until `projection_membership` holds an ACTIVE row for
/// `(block_id, user_id)` with the expected role.
async fn await_block_member_active(
    pool: &PgPool,
    block_id: Uuid,
    user_id: &UserId,
    role: Role,
) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let row: Option<(String, String)> = sqlx::query_as(
            "SELECT role, state FROM projection_membership WHERE block_id = $1 AND user_id = $2",
        )
        .bind(block_id)
        .bind(user_id.as_str())
        .fetch_optional(pool)
        .await
        .map_err(|e| anyhow!("reading projection_membership failed: {e}"))?;
        if row
            .as_ref()
            .is_some_and(|(token, state)| token == role.as_str() && state == "active")
        {
            return Ok(());
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: block membership ({block_id}, {user_id:?}) = {row:?}, \
                 expected {:?}/active within {PROJECTION_DEADLINE:?}",
                role.as_str()
            );
        }
    }
}

/// EAPPEND a `ProjectMembershipEvent` to a SierraDB stream (CBOR payload),
/// mirroring `eappend_membership` in `membership_round_trip.rs`.
async fn eappend_project_membership(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    event: &ProjectMembershipEvent,
) -> Result<()> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    let now_ms = chrono::Utc::now()
        .timestamp_millis()
        .try_into()
        .unwrap_or(0u64);
    let mut conn = client.get_multiplexed_async_connection().await?;
    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_name)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(&payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
    Ok(())
}

/// Postgres + SierraDB + every projector this file reads from (season, block,
/// block membership, project membership) and a SierraDB-backed
/// `CommandService`.
async fn init_project_membership() -> Result<(
    PgPool,
    Arc<RedisClient>,
    CommandService,
    ContainerAsync<Postgres>,
    ContainerAsync<fixtures::SierraDbImage>,
)> {
    let (pool, pg_guard) = fixtures::spawn_postgres().await?;
    let (sierra_client, _sierra_conn, sierra_guard) = fixtures::spawn_sierradb().await?;
    let flush = infra::projectors::ProjectorFlushConfig::test_profile();

    let _pmp =
        spawn_project_membership_projector(pool.clone(), Arc::clone(&sierra_client), flush).await?;
    // The project fallback resolves the project THROUGH `projection_season`.
    let _sp = spawn_season_projector(pool.clone(), Arc::clone(&sierra_client), flush).await?;
    // Block scope: `projection_block` feeds both membership scopes.
    let _bp = spawn_block_projector(pool.clone(), Arc::clone(&sierra_client), flush).await?;
    let _mp = spawn_membership_projector(pool.clone(), Arc::clone(&sierra_client), flush).await?;
    // Let the subscriptions settle before appending events.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cmd_service = CommandService::new(
        sierra_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| anyhow!("SierraDB connection failed: {e}"))?,
    );
    Ok((pool, sierra_client, cmd_service, pg_guard, sierra_guard))
}

/// Tier-3 (task 2.2 / 2.5): the project-membership projector is idempotent
/// under **event redelivery** and models a revocation as a state transition.
///
/// The upsert is version-guarded, so the assertions are:
///
/// 1. a redelivered bootstrap does not create a second row and does not change
///    the row (still one row, active, `costume_designer`);
/// 2. a grant for another user adds exactly one row;
/// 3. a revoke flips `state` to `revoked` and keeps the row (the audit trail of
///    the grant stays readable) — the authorization predicates only match
///    `active`, so a revoked grant is inert.
#[tokio::test]
async fn project_membership_projector_is_idempotent_under_redelivery() -> Result<()> {
    let (pool, redis_client, _cmd_svc, _pg, _sierra) = init_project_membership().await?;
    let project_id = ProjectId::from_uuid(Uuid::now_v7());
    let owner = UserId::from_sub("project-owner");
    let supervisor = UserId::from_sub("project-supervisor");
    // Stream id == project id (category "project_membership"), matching the
    // command path (`SeasonCommandsImpl::bootstrap_project_owner`).
    let stream_id = format!("project_membership-{}", project_id.0);

    let bootstrap = ProjectMembershipEvent::ProjectOwnerBootstrapped {
        project_id,
        user_id: owner.clone(),
        role: Role::CostumeDesigner,
    };
    eappend_project_membership(
        &redis_client,
        &stream_id,
        "ProjectOwnerBootstrapped",
        "EMPTY",
        &bootstrap,
    )
    .await?;
    await_projected_grant(&pool, project_id, &owner, ("costume_designer", "active")).await?;

    // Redelivery of the same logical event (fresh SierraDB append → new event.id).
    eappend_project_membership(
        &redis_client,
        &stream_id,
        "ProjectOwnerBootstrapped",
        "0",
        &bootstrap,
    )
    .await?;
    // A distinct *second* user (a grant, version 1 by the store's own count).
    let grant = ProjectMembershipEvent::ProjectRoleGranted {
        project_id,
        user_id: supervisor.clone(),
        role: Role::WardrobeSupervisor,
    };
    eappend_project_membership(&redis_client, &stream_id, "ProjectRoleGranted", "1", &grant)
        .await?;
    await_projected_grant(
        &pool,
        project_id,
        &supervisor,
        ("wardrobe_supervisor", "active"),
    )
    .await?;
    await_project_grant_count(&pool, project_id, 2).await?;

    // The redelivered bootstrap must not have changed the owner's row.
    assert_eq!(
        projected_grant(&pool, project_id, &owner).await?,
        Some(("costume_designer".to_owned(), "active".to_owned())),
        "a redelivered bootstrap must keep the single owner row intact"
    );

    // Revocation is a state transition, not a delete.
    let revoke = ProjectMembershipEvent::ProjectRoleRevoked {
        project_id,
        user_id: supervisor.clone(),
    };
    eappend_project_membership(
        &redis_client,
        &stream_id,
        "ProjectRoleRevoked",
        "2",
        &revoke,
    )
    .await?;
    await_projected_grant(
        &pool,
        project_id,
        &supervisor,
        ("wardrobe_supervisor", "revoked"),
    )
    .await?;
    assert_eq!(
        projected_grant(&pool, project_id, &supervisor).await?,
        Some(("wardrobe_supervisor".to_owned(), "revoked".to_owned())),
        "a revocation must keep the row and only flip its state"
    );

    // ... and the read side stops authorizing it.
    let repo = MembershipRepositoryImpl::new(pool.clone());
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::new(), supervisor.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        None,
        "a revoked grant must not resolve a role"
    );

    Ok(())
}

/// Tier-4 (task 2.4): creating a season bootstraps the creator's
/// **project-scoped** `costume_designer`, and the effective resolution accepts
/// that season even though it has **no block**.
///
/// This is the whole point of the change: before it, a block-less season was
/// role-less by construction, so the `829` D1 upload (`X-Declared-Season`)
/// answered `403 ai-import.forbidden` for the production's own costume designer.
#[tokio::test]
async fn season_creation_bootstraps_the_project_scoped_owner_role() -> Result<()> {
    let (pool, _redis_client, cmd_svc, _pg, _sierra) = init_project_membership().await?;
    let seasons = SeasonCommandsImpl::new(cmd_svc);
    let repo = MembershipRepositoryImpl::new(pool.clone());

    let project_id = ProjectId::from_uuid(Uuid::now_v7());
    let season_id = Uuid::now_v7();
    let creator = UserId::from_sub("season-creator");

    seasons
        .create(
            creator.clone(),
            CreateSeason {
                id: season_id,
                project_id,
                number: 1,
                title: Some("Block-less season".to_owned()),
            },
        )
        .await
        .map_err(|e| anyhow!(e.to_string()))?;
    await_season_projected(&pool, season_id).await?;

    // The bootstrap is part of the command path, not of a projector: the grant
    // exists as an event and is projected independently of the season row.
    await_projected_grant(&pool, project_id, &creator, ("costume_designer", "active")).await?;

    // No block exists in this season …
    let blocks: i64 =
        sqlx::query_scalar("SELECT count(*) FROM projection_block WHERE season_id = $1")
            .bind(season_id)
            .fetch_one(&pool)
            .await
            .map_err(|e| anyhow!("counting blocks failed: {e}"))?;
    assert_eq!(blocks, 0, "this test needs a season without blocks");

    // … so the block scope misses, and only the project scope can answer.
    let season = SeasonId::from_uuid(season_id);
    assert!(
        !repo
            .has_active_costume_role_in_season(season, creator.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        "the block-scoped predicate must miss on a block-less season"
    );
    assert_eq!(
        repo.effective_costume_role_in_season(season, creator.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        Some(Role::CostumeDesigner),
        "the season creator must be authorized through the project scope"
    );

    // Idempotency across a second season of the same project: the aggregate's
    // state hook turns the repeat bootstrap into a no-op, so there is still
    // exactly ONE row and the season creation succeeds.
    seasons
        .create(
            creator.clone(),
            CreateSeason {
                id: Uuid::now_v7(),
                project_id,
                number: 2,
                title: Some("Second season".to_owned()),
            },
        )
        .await
        .map_err(|e| anyhow!(e.to_string()))?;
    await_project_grant_count(&pool, project_id, 1).await?;

    Ok(())
}

/// Tier-4 (task 2.3 / 3.3): effective resolution precedence and fail-closed
/// behaviour, against real SQL.
///
/// 1. **Block first** — a user holding `costume_assistant` in a block of the
///    season *and* `costume_designer` at project scope resolves to the
///    **block** role inside that season (both scopes coexist, neither overwrites
///    the other).
/// 2. **Project fallback** — the same project grant authorizes a *different*,
///    block-less season of the same project.
/// 3. **Tenant boundary** — it does not authorize a season of another project.
/// 4. **Fail closed** — an unknown season, an unknown user and a revoked grant
///    are all `None`.
/// 5. **Report archive keeps the block-only resolution** (`3.3`): the project
///    grant never reaches `has_active_report_archive_role_in_season`.
#[tokio::test]
async fn effective_role_resolves_block_first_then_the_seasons_project() -> Result<()> {
    let (pool, redis_client, cmd_svc, _pg, _sierra) = init_project_membership().await?;
    let seasons = SeasonCommandsImpl::new(cmd_svc.clone());
    let blocks = BlockCommandsImpl::new(cmd_svc.clone());
    let membership = MembershipCommandsImpl::new(cmd_svc);
    let repo = MembershipRepositoryImpl::new(pool.clone());

    let project_id = ProjectId::from_uuid(Uuid::now_v7());
    let foreign_project = ProjectId::from_uuid(Uuid::now_v7());
    let blocky_season = Uuid::now_v7();
    let blockless_season = Uuid::now_v7();
    let foreign_season = Uuid::now_v7();
    let user = UserId::from_sub("two-scope-costumer");

    for (id, number, project) in [
        (blocky_season, 1, project_id),
        (blockless_season, 2, project_id),
        (foreign_season, 3, foreign_project),
    ] {
        seasons
            .create(
                UserId::from_sub("season-creator"),
                CreateSeason {
                    id,
                    project_id: project,
                    number,
                    title: None,
                },
            )
            .await
            .map_err(|e| anyhow!(e.to_string()))?;
        await_season_projected(&pool, id).await?;
    }

    // Block scope: `user` is a costume ASSISTANT in a block of `blocky_season`.
    let block_id = BlockId::from_uuid(Uuid::now_v7());
    blocks
        .create(
            UserId::from_sub("block-creator"),
            CreateBlock {
                id: block_id.0,
                season_id: SeasonId::from_uuid(blocky_season),
                project_id,
                number: 1,
                start_date: None,
                end_date: None,
            },
        )
        .await
        .map_err(|e| anyhow!(e.to_string()))?;
    membership
        .bootstrap_owner(
            UserId::from_sub("block-creator"),
            BootstrapOwner {
                block_id,
                project_id,
                user_id: user.clone(),
                role: Role::CostumeAssistant,
            },
        )
        .await
        .map_err(|e| anyhow!(e.to_string()))?;

    // Project scope: the same user holds costume DESIGNER on the project.
    // The stream already carries the season creator's bootstrap event, so the
    // grant is appended at "any version" — the store enforces the exact
    // ordering, this test only needs the event to exist.
    let stream_id = format!("project_membership-{}", project_id.0);
    eappend_project_membership(
        &redis_client,
        &stream_id,
        "ProjectRoleGranted",
        "0",
        &ProjectMembershipEvent::ProjectRoleGranted {
            project_id,
            user_id: user.clone(),
            role: Role::CostumeDesigner,
        },
    )
    .await?;
    await_projected_grant(&pool, project_id, &user, ("costume_designer", "active")).await?;
    await_block_projected(&pool, block_id.0).await?;
    await_block_member_active(&pool, block_id.0, &user, Role::CostumeAssistant).await?;

    // (1) Block first: inside the block's season the BLOCK role wins, so the
    //     two-scope holder must be distinguishable from a project-only one.
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::from_uuid(blocky_season), user.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        Some(Role::CostumeAssistant),
        "the block-scoped role must win inside its own season"
    );

    // (2) Project fallback on the block-less season of the same project.
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::from_uuid(blockless_season), user.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        Some(Role::CostumeDesigner),
        "the project grant must authorize a block-less season of that project"
    );

    // (3) Tenant boundary + (4) fail closed.
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::from_uuid(foreign_season), user.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        None,
        "a project grant must not authorize another project's season"
    );
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::new(), user.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        None,
        "an unknown season must fail closed"
    );
    assert_eq!(
        repo.effective_costume_role_in_season(
            SeasonId::from_uuid(blockless_season),
            UserId::from_sub("stranger")
        )
        .await
        .map_err(|e| anyhow!(e.to_string()))?,
        None,
        "a user with no role in either scope must be denied"
    );

    // (5) The narrower report-archive predicate must NOT gain the project
    //     fallback (design D6 / the change's explicit risk mitigation).
    assert!(
        !repo
            .has_active_report_archive_role_in_season(
                SeasonId::from_uuid(blockless_season),
                user.clone()
            )
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        "a project-scoped costume_designer must not gain manual report archival"
    );
    assert!(
        !repo
            .has_active_report_archive_role_in_season(
                SeasonId::from_uuid(blocky_season),
                user.clone()
            )
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        "a block-scoped costume_assistant must not hold the archive role either"
    );

    // A revocation takes the project fallback away again (state transition).
    eappend_project_membership(
        &redis_client,
        &stream_id,
        "ProjectRoleRevoked",
        // SierraDB versions are 0-based indexes of the last appended event:
        // the bootstrap sits at 0, the grant at 1.
        "1",
        &ProjectMembershipEvent::ProjectRoleRevoked {
            project_id,
            user_id: user.clone(),
        },
    )
    .await?;
    await_projected_grant(&pool, project_id, &user, ("costume_designer", "revoked")).await?;
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::from_uuid(blockless_season), user.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        None,
        "a revoked project grant must not authorize the block-less season"
    );
    // The block scope is untouched by the project revocation.
    assert_eq!(
        repo.effective_costume_role_in_season(SeasonId::from_uuid(blocky_season), user.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?,
        Some(Role::CostumeAssistant),
        "a project revocation must not touch the block-scoped role"
    );

    Ok(())
}

/// Task 2.4's command shape, pinned: `GrantProjectRole` / `RevokeProjectRole`
/// are only reachable through the aggregate (there is no HTTP surface yet), so
/// the grant path this test drives IS the future adapter contract.
///
/// Guards the allowlist boundary the aggregate owns (task 1.2): an `ops_admin`
/// grant is refused by the aggregate and appends no event.
#[tokio::test]
async fn the_aggregate_refuses_a_non_costume_project_grant() -> Result<()> {
    use kameo_es::command_service::ExecuteExt;
    use sierradb_client::ExpectedVersion;

    let (pool, _redis_client, cmd_svc, _pg, _sierra) = init_project_membership().await?;
    let project_id = ProjectId::from_uuid(Uuid::now_v7());

    let result = breakdown_core::project_membership::ProjectMembership::execute(
        &cmd_svc,
        project_id.0,
        GrantProjectRole {
            project_id,
            user_id: UserId::from_sub("would-be-ops"),
            role: Role::OpsAdmin,
        },
    )
    .expected_version(ExpectedVersion::Any)
    .await;
    assert!(
        result.is_err(),
        "an ops_admin grant must be rejected by the aggregate"
    );

    // No event reached the store, so no projection row can exist.
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(
        projected_grant(&pool, project_id, &UserId::from_sub("would-be-ops")).await?,
        None,
        "a refused grant must not be projected"
    );

    Ok(())
}
