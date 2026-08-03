// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! Explicit one-time importer for deployments using the pre-Settings GDrive
//! environment variables.
//!
//! The legacy variables are intentionally referenced only in this dedicated
//! migration command. The API binary and all report workers load GDrive
//! material exclusively through Settings/Vault.

use std::env;

use anyhow::{Context, Result, bail};
use breakdown_core::error::DomainError;
use breakdown_core::settings::ports::{CredentialVault, SettingsCommands, SettingsRepository};
use breakdown_core::settings::{CreateCredentialBinding, RotateCredentialBinding};
use breakdown_core::shared::UserId;
use infra::event_store::SettingsCommandsImpl;
use infra::queries::SettingsRepositoryImpl;
use infra::reporting::OpenDalReportArchiveStorage;
use infra::vault::VaultClient;
use kameo_es::command_service::CommandService;
use redis::Client as RedisClient;
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

struct Options {
    settings_id: Uuid,
    actor: UserId,
    rotate: bool,
}

fn parse_options() -> Result<Options> {
    let mut args = env::args().skip(1);
    let mut settings_id = None;
    let mut actor = None;
    let mut rotate = false;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--settings-id" => {
                let value = args.next().context("--settings-id requires a UUID")?;
                settings_id = Some(Uuid::parse_str(&value).context("invalid --settings-id")?);
            }
            "--actor" => {
                let value = args.next().context("--actor requires a subject")?;
                if value.trim().is_empty() {
                    bail!("--actor must not be empty");
                }
                actor = Some(UserId::from_sub(value));
            }
            "--rotate" => rotate = true,
            "--confirm-legacy-env" => {}
            _ => bail!(
                "usage: migrate_gdrive_credentials --confirm-legacy-env --settings-id <UUID> --actor <SUB> [--rotate]"
            ),
        }
    }

    let settings_id = settings_id.context("--settings-id is required")?;
    let actor = actor.context("--actor is required")?;
    if !env::args().any(|arg| arg == "--confirm-legacy-env") {
        bail!("refusing to read legacy credentials without --confirm-legacy-env");
    }
    Ok(Options {
        settings_id,
        actor,
        rotate,
    })
}

fn legacy_bundle() -> Result<breakdown_core::settings::ports::GDriveCredentialBundle> {
    let client_id = env::var("REPORT_BACKUP_GDRIVE_CLIENT_ID")
        .context("REPORT_BACKUP_GDRIVE_CLIENT_ID is required for migration")?;
    let client_secret = env::var("REPORT_BACKUP_GDRIVE_CLIENT_SECRET")
        .context("REPORT_BACKUP_GDRIVE_CLIENT_SECRET is required for migration")?;
    let refresh_token = env::var("REPORT_BACKUP_GDRIVE_REFRESH_TOKEN")
        .context("REPORT_BACKUP_GDRIVE_REFRESH_TOKEN is required for migration")?;
    let root_folder_id = env::var("REPORT_BACKUP_GDRIVE_ROOT").ok();
    breakdown_core::settings::ports::GDriveCredentialBundle::try_new(
        client_id,
        client_secret,
        refresh_token,
        root_folder_id,
    )
    .map_err(anyhow::Error::msg)
}

async fn run() -> Result<()> {
    let options = parse_options()?;
    let bundle = legacy_bundle()?;

    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5432/breakdown".into());
    let sierradb_url = env::var("SIERRADB_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:9090/?protocol=resp3".into());
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&database_url)
        .await
        .context("connect PostgreSQL")?;
    let redis = RedisClient::open(sierradb_url).context("open SierraDB client")?;
    let connection = redis
        .get_multiplexed_async_connection()
        .await
        .context("connect SierraDB")?;
    let command_service = CommandService::new(connection);
    let settings_repo = SettingsRepositoryImpl::new(pool);
    let settings_commands = SettingsCommandsImpl::new(command_service);
    let vault = VaultClient::from_env().map_err(anyhow::Error::msg)?;

    let existing = match settings_repo.find_by_id(options.settings_id).await {
        Ok(view) => Some(view),
        Err(DomainError::NotFound(_)) => None,
        Err(error) => return Err(anyhow::Error::msg(error)),
    };
    if let Some(view) = &existing {
        if view.provider != "gdrive" {
            bail!("the Settings id is already bound to another provider");
        }
        if !options.rotate
            && view.binding_state == breakdown_core::settings::views::CredentialBindingState::Active
        {
            let current = vault
                .fetch_gdrive(options.settings_id, &view.vault_key_id)
                .await
                .map_err(anyhow::Error::msg)?;
            if current.has_same_material(&bundle) {
                // Idempotent success: do not rewrite Vault or append an event.
                return Ok(());
            }
            bail!("an active GDrive binding exists; pass --rotate explicitly");
        }
        if !options.rotate {
            bail!("the Settings id already exists; pass --rotate explicitly");
        }
    }

    let binding = vault
        .store_gdrive(options.settings_id, bundle)
        .await
        .map_err(anyhow::Error::msg)?;
    let binding_ref = breakdown_core::settings::ports::VaultBinding {
        vault_key_id: binding.vault_key_id.clone(),
        vault_version: binding.vault_version,
    };
    // Constructing the operator performs the adapter-level validation before
    // any reference-only event is appended. It never logs or returns material.
    if let Err(error) =
        OpenDalReportArchiveStorage::validate_from_vault(&vault, options.settings_id, &binding_ref)
            .await
    {
        if let Err(destroy_err) = vault
            .destroy(options.settings_id, &binding.vault_key_id)
            .await
        {
            tracing::warn!(
                vault_key_id = %binding.vault_key_id,
                error = %destroy_err,
                "failed to destroy superseded GDrive binding"
            );
        }
        bail!("GDrive provider validation failed: {error}");
    }

    let command_result = if let Some(view) = existing.clone() {
        settings_commands
            .rotate(
                options.actor,
                RotateCredentialBinding {
                    id: options.settings_id,
                    provider: "gdrive".into(),
                    vault_key_id: binding.vault_key_id.clone(),
                    vault_version: binding.vault_version,
                    version: view.version,
                },
            )
            .await
            .map(|version| (options.settings_id, version))
            .map_err(anyhow::Error::msg)
    } else {
        settings_commands
            .create(
                options.actor,
                CreateCredentialBinding {
                    id: options.settings_id,
                    provider: "gdrive".into(),
                    vault_key_id: binding.vault_key_id.clone(),
                    vault_version: binding.vault_version,
                },
            )
            .await
            .map_err(anyhow::Error::msg)
    };

    match command_result {
        Ok(_) => {
            if let Some(view) = existing
                && let Err(error) = vault.destroy(options.settings_id, &view.vault_key_id).await
            {
                tracing::warn!(
                    vault_key_id = %view.vault_key_id,
                    error = %error,
                    "superseded GDrive binding cleanup failed"
                );
            }
            Ok(())
        }
        Err(error) => {
            if let Err(destroy_err) = vault
                .destroy(options.settings_id, &binding.vault_key_id)
                .await
            {
                tracing::warn!(
                    vault_key_id = %binding.vault_key_id,
                    error = %destroy_err,
                    "failed to destroy superseded GDrive binding"
                );
            }
            Err(error)
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    run().await
}
