// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Test-only helpers for spinning up real external resources.
//!
//! Everything in this module is compiled only when the `testing` cargo feature is
//! enabled, so it never becomes part of a production build.
//!
//! # Postgres harness
//!
//! `spawn_postgres()` starts an ephemeral PostgreSQL container via the
//! [`testcontainers_modules::postgres::Postgres`] image and returns a
//! ready-to-use [`sqlx::PgPool`] together with the owning
//! [`ContainerAsync`](testcontainers::ContainerAsync) guard. Dropping the guard
//! tears the container down, guaranteeing isolation between tests.
//!
//! On return, the projection schema has already been applied through
//! [`sqlx::migrate!`] from `crates/infra/migrations`. Migration mismatches are
//! propagated as hard errors.
//!
//! ## Local container reuse
//!
//! Starting a fresh container per test adds a few seconds of overhead. For local
//! development speed you can opt into the Testcontainers reuse mechanism:
//!
//! ```bash
//! export TESTCONTAINERS_REUSE=1
//! cargo test -p integration-tests
//! ```
//!
//! When reuse is enabled the container may be kept alive across test runs. CI
//! runners must **never** set this variable; CI always uses fresh containers.

use std::env;

use anyhow::Result;
use sqlx::PgPool;
use testcontainers::runners::AsyncRunner;
use testcontainers::{ContainerAsync, ContainerRequest, ImageExt, ReuseDirective};
use testcontainers_modules::postgres::Postgres as PostgresImage;

/// Starts an ephemeral Postgres container and returns a configured pool.
///
/// The returned pool is connected to a fresh, empty Postgres instance. The
/// projection schema from `crates/infra/migrations` is applied before the
/// function returns. Dropping the `ContainerAsync` guard stops and removes the
/// container.
pub async fn spawn_postgres() -> Result<(PgPool, ContainerAsync<PostgresImage>)> {
    let request = build_postgres_container_request();
    let container = request.start().await?;

    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(5432).await?;
    let url = format!("postgres://postgres:postgres@{host}:{port}/postgres");

    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await?;

    // Wait until Postgres is actually accepting queries.
    sqlx::query("SELECT 1").fetch_one(&pool).await?;

    // Apply projection migrations. Mismatches intentionally fail the test.
    sqlx::migrate!("./migrations").run(&pool).await?;

    Ok((pool, container))
}

fn build_postgres_container_request() -> ContainerRequest<PostgresImage> {
    let image = PostgresImage::default();

    if env::var("TESTCONTAINERS_REUSE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        image.with_reuse(ReuseDirective::Always)
    } else {
        image.into()
    }
}
