// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (pi)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! AI import queue worker loops (issue #214).
//!
//! The concurrency limiter (`PgAiConcurrencyLimiter`) and its reclaimer live
//! in the composition root (`main.rs`); this module owns the *worker tasks*
//! that actually claim and process jobs. Each loop:
//!
//! 1. claims the next runnable job of its kind (`claim_next_kind_reconciling`,
//!    which also releases the permit orphaned by a dead worker — issue #180),
//!    learning the job's `user_id`;
//! 2. loads the source bytes **outside** the permit (a slow or hung fetch of a
//!    large PDF must not hold capacity), failing the job terminally if the
//!    durable bytes are gone;
//! 3. resolves the job's per-user AI config + vaulted API key and builds the
//!    matching LLM client;
//! 4. routes the already-claimed job through
//!    [`super::runtime::AiWorkerRuntime::run_job_as`], so the permit lifecycle
//!    (acquire → renew → release) and the `AiJobGuard` tracked for
//!    [`super::runtime::AiWorkerRuntime::drain`] are managed in one place.
//!
//! Routing through `run_job_as` is the whole point: before this module the
//! limiter was public API that nothing constructed, so jobs never consumed a
//! permit and the `AI_IMPORT_MAX_CONCURRENT_JOBS_*` ceilings were documentation
//! only.

use std::sync::Arc;
use std::time::Duration;

use super::heartbeat::LeaseHeartbeat;
use super::heartbeat::claim_lost;
use breakdown_core::ai::{AiImportBounds, AiImportJobId, AiImportQueue, DocumentKind, LlmProvider};
use breakdown_core::error::DomainError;
use breakdown_core::settings::CredentialVault;
use tokio::sync::watch;
use tracing::{info, warn};

use super::client::OpenAiCompatibleChatClient;
use super::ollama::OllamaChatClient;
use super::pdf::PdfTextExtractor;
use super::preview_store::AiDocumentSource;
use super::preview_store::AiPreviewStore;
use super::queue::PgAiImportQueue;
use super::runtime::AiWorkerRuntime;
use super::workers::{ScheduleImportWorker, ScriptImportWorker};
use crate::queries::ai_config::{AiConfigRepositoryImpl, AiWorkerConfig};

/// How long a worker sleeps when the queue is empty before polling again.
/// Bounded so a worker notices a shutdown signal within one interval.
const EMPTY_QUEUE_SLEEP: Duration = Duration::from_secs(2);

/// Shutdown signal shared between the composition root and every worker task.
///
/// The composition root owns the sender and sets it to `true` on SIGTERM; each
/// worker holds a receiver cloned from it. Using `tokio::sync::watch` (already
/// a workspace dependency) keeps the cancellation flag allocation-free on the
/// hot path — workers just read a `bool`.
pub type ShutdownSignal = watch::Receiver<bool>;

/// Build and return the shutdown channel pair. The caller keeps the sender and
/// sets it to `true` to request that every worker stop; each spawned worker
/// receives a clone of the receiver.
pub fn shutdown_signal() -> (watch::Sender<bool>, ShutdownSignal) {
    watch::channel(false)
}

/// Shared dependencies for one AI import worker loop.
///
/// Bundling the queue, source, preview store, config repo, credentials and
/// bounds into one struct keeps the spawn/tick functions' argument counts
/// clippy-clean (`clippy::too_many_arguments`) and makes the composition
/// root's wiring read as "build deps, spawn workers".
pub struct WorkerDeps {
    pub runtime: Arc<AiWorkerRuntime>,
    pub queue: Arc<PgAiImportQueue>,
    pub source: Arc<dyn AiDocumentSource>,
    pub previews: Arc<dyn AiPreviewStore>,
    pub config_repo: AiConfigRepositoryImpl,
    pub credentials: Arc<dyn CredentialVault>,
    pub bounds: AiImportBounds,
}

/// Spawn the script import worker loop. The returned handle must be kept alive
/// and joined during graceful shutdown (issue #214): the task holds a permit
/// for the duration of each job, and `PermitReclaimer::shutdown` waits for
/// every such holder to drop.
pub fn spawn_script_import_worker(
    deps: WorkerDeps,
    shutdown: ShutdownSignal,
) -> tokio::task::JoinHandle<()> {
    spawn_worker(deps, shutdown, DocumentKind::Script)
}

/// Spawn the schedule import worker loop. See
/// [`spawn_script_import_worker`] for the shutdown-ordering contract.
pub fn spawn_schedule_import_worker(
    deps: WorkerDeps,
    shutdown: ShutdownSignal,
) -> tokio::task::JoinHandle<()> {
    spawn_worker(deps, shutdown, DocumentKind::Schedule)
}

/// The worker loop proper, shared between the script and schedule workers.
/// The document kind selects the kind-specific poll implementation (the only
/// thing that differs between the two workers).
fn spawn_worker(
    deps: WorkerDeps,
    shutdown: ShutdownSignal,
    kind: DocumentKind,
) -> tokio::task::JoinHandle<()> {
    let label = match kind {
        DocumentKind::Script => "script",
        DocumentKind::Schedule => "schedule",
    };
    let worker_id = format!("{label}-{}", uuid::Uuid::now_v7());
    tokio::spawn(async move {
        let mut shutdown = shutdown;
        info!(worker_id, "{label} import worker started");
        loop {
            if *shutdown.borrow() {
                info!(worker_id, "{label} import worker shutting down");
                break;
            }

            let result = match kind {
                DocumentKind::Script => script_worker_tick(&deps, &worker_id, &mut shutdown).await,
                DocumentKind::Schedule => {
                    schedule_worker_tick(&deps, &worker_id, &mut shutdown).await
                }
            };

            if let Err(error) = result {
                warn!(worker_id, %error, "{label} worker tick failed");
                // Don't tight-loop on a persistent error; back off and let the
                // shutdown signal wake us.
                tokio::select! {
                    _ = shutdown.changed() => break,
                    _ = tokio::time::sleep(EMPTY_QUEUE_SLEEP) => {}
                }
            }
        }
    })
}

/// Build the OpenAI-compatible LLM client for one job.
///
/// The API key is per-user and lives in the vault; the worker loop fetches it
/// with the config's `vault_key_id` and never stores it outside the client.
async fn build_openai_client(
    provider: LlmProvider,
    api_key: String,
    timeout: Duration,
) -> Result<Arc<OpenAiCompatibleChatClient>, DomainError> {
    let client = OpenAiCompatibleChatClient::new(provider, api_key, timeout).await?;
    Ok(Arc::new(client))
}

/// Build the Ollama client for one job. Ollama is routed through its own
/// client (its curated base URL is plain HTTP — sending a vaulted bearer token
/// there would leak it, CWE-319).
fn build_ollama_client(timeout: Duration) -> Result<Arc<OllamaChatClient>, DomainError> {
    let client = OllamaChatClient::new(3, timeout)?;
    Ok(Arc::new(client))
}

/// Resolve the user's active AI config for one job.
///
/// The job carries `user_id` but not a config id, so the loop resolves the
/// user's active config first. A missing config fails the job terminally — the
/// worker never blocks retry on a misconfiguration it cannot fix.
async fn resolve_config(
    config_repo: &AiConfigRepositoryImpl,
    user_id: &breakdown_core::shared::UserId,
    kind: DocumentKind,
) -> Result<AiWorkerConfig, DomainError> {
    config_repo
        .find_worker_config(user_id, kind)
        .await?
        .ok_or_else(|| DomainError::ValidationError("no active AI import configuration".to_owned()))
}

/// Fetch the vaulted API key for an OpenAI-compatible provider.
///
/// Ollama is deliberately excluded: its curated base URL is plain HTTP, so it
/// needs no bearer token — fetching one would issue an unnecessary Vault
/// request (and an invalid key reference would fail the job). The key is
/// required for every other provider; a missing key fails the job terminally.
async fn fetch_api_key(
    credentials: &dyn CredentialVault,
    config: &AiWorkerConfig,
) -> Result<String, DomainError> {
    let secret = credentials
        .fetch(config.config_id, &config.vault_key_id)
        .await?;
    Ok(secret.as_str().to_owned())
}

/// One script-worker poll: claim → load → resolve config → process under permit.
async fn script_worker_tick(
    deps: &WorkerDeps,
    worker_id: &str,
    shutdown: &mut ShutdownSignal,
) -> Result<(), DomainError> {
    // Claim first (reconciling releases an orphan permit), so we learn the
    // job's user_id before acquiring capacity — the permit is charged to the
    // user whose work it is, never to a synthetic per-worker id.
    let (job, released) = match deps
        .queue
        .claim_next_kind_reconciling(worker_id, DocumentKind::Script)
        .await?
    {
        Some(pair) => pair,
        None => {
            tokio::select! {
                _ = shutdown.changed() => {}
                _ = tokio::time::sleep(EMPTY_QUEUE_SLEEP) => {}
            }
            return Ok(());
        }
    };

    if released.is_some() {
        info!(
            worker_id,
            job_id = %job.id.as_uuid(),
            "reclaimed orphaned script job"
        );
    }

    // Load the source *outside* the permit: a slow or hung fetch of a large
    // PDF must not hold capacity. A failed load fails the job terminally —
    // the existing helper chooses the terminal state by error kind.
    // Start a claim heartbeat before source loading (issue #214). A slow or
    // hung load of a large PDF must not outlive the claim lease: another
    // worker could otherwise reclaim the job while this one is still loading.
    // Mirrors the protection the existing `run_once_with_permit` workers apply
    // in `workers.rs`.
    let heartbeat = deps
        .queue
        .lease_window()
        .and_then(|lease| LeaseHeartbeat::start(deps.queue.clone(), job.id, worker_id, lease));

    let bytes = match deps.source.load(&job.source_handle).await {
        Ok(bytes) => bytes,
        Err(error) => {
            if let Some(heartbeat) = heartbeat {
                heartbeat.stop();
            }
            warn!(
                worker_id,
                job_id = %job.id.as_uuid(),
                %error,
                "failed to load script source; failing job"
            );
            super::workers::fail_payload_load(&*deps.queue, job.id, worker_id, &error).await?;
            return Ok(());
        }
    };

    if claim_lost(heartbeat.as_ref()) {
        // Another worker owns the job now; every terminal write of ours would be
        // rejected, so stop before any further work.
        return Err(DomainError::Conflict(format!(
            "AI import job {} was reclaimed while its source loaded",
            job.id.as_uuid()
        )));
    }
    if let Some(heartbeat) = heartbeat {
        heartbeat.stop();
    }

    let user_id = job.user_id.clone();
    let config = match resolve_config(&deps.config_repo, &user_id, DocumentKind::Script).await {
        Ok(config) => config,
        Err(error) => {
            warn!(
                worker_id,
                job_id = %job.id.as_uuid(),
                %error,
                "failed to resolve AI config; failing job"
            );
            deps.queue
                .mark_failed(
                    job.id,
                    worker_id,
                    &error.to_string(),
                    matches!(error, DomainError::ServiceUnavailable(_)),
                )
                .await?;
            return Ok(());
        }
    };

    // Fetch the API key only for OpenAI-compatible providers. Ollama needs no
    // bearer token (its base URL is plain HTTP), so fetching one would issue
    // an unnecessary Vault request (issue #214).
    let api_key = match config.provider {
        LlmProvider::Ollama => String::new(),
        _ => match fetch_api_key(&*deps.credentials, &config).await {
            Ok(key) => key,
            Err(error) => {
                warn!(
                    worker_id,
                    job_id = %job.id.as_uuid(),
                    %error,
                    "failed to fetch AI credential; failing job"
                );
                deps.queue
                    .mark_failed(
                        job.id,
                        worker_id,
                        &error.to_string(),
                        matches!(error, DomainError::ServiceUnavailable(_)),
                    )
                    .await?;
                return Ok(());
            }
        },
    };

    // Route the already-claimed job through the runtime so the permit
    // lifecycle and the AiJobGuard (tracked for drain) are managed in one
    // place. `Ok(None)` means the ceiling is saturated — hand the claim back
    // so the job is runnable immediately and is not charged a retry.
    let result = match config.provider {
        LlmProvider::Ollama => {
            let client =
                match build_ollama_client(Duration::from_secs(deps.bounds.request_timeout_secs)) {
                    Ok(client) => client,
                    Err(error) => {
                        warn!(
                            worker_id,
                            job_id = %job.id.as_uuid(),
                            %error,
                            "failed to build Ollama client; failing job"
                        );
                        deps.queue
                            .mark_failed(job.id, worker_id, &error.to_string(), false)
                            .await?;
                        return Ok(());
                    }
                };
            let worker = ScriptImportWorker {
                queue: deps.queue.clone(),
                client,
                previews: deps.previews.clone(),
                extractor: PdfTextExtractor::new(
                    usize::try_from(deps.bounds.max_document_bytes).unwrap_or(usize::MAX),
                    Duration::from_secs(deps.bounds.request_timeout_secs),
                ),
                provider: config.provider,
                model: config.model,
                prompt: config.prompt,
                bounds: deps.bounds,
            };
            deps.runtime
                .run_job_as(user_id.as_str(), worker_id, || {
                    worker.process(&job, worker_id, &bytes)
                })
                .await
        }
        _ => {
            let client = match build_openai_client(
                config.provider,
                api_key,
                Duration::from_secs(deps.bounds.request_timeout_secs),
            )
            .await
            {
                Ok(client) => client,
                Err(error) => {
                    warn!(
                        worker_id,
                        job_id = %job.id.as_uuid(),
                        %error,
                        "failed to build LLM client; failing job"
                    );
                    deps.queue
                        .mark_failed(job.id, worker_id, &error.to_string(), false)
                        .await?;
                    return Ok(());
                }
            };
            let worker = ScriptImportWorker {
                queue: deps.queue.clone(),
                client,
                previews: deps.previews.clone(),
                extractor: PdfTextExtractor::new(
                    usize::try_from(deps.bounds.max_document_bytes).unwrap_or(usize::MAX),
                    Duration::from_secs(deps.bounds.request_timeout_secs),
                ),
                provider: config.provider,
                model: config.model,
                prompt: config.prompt,
                bounds: deps.bounds,
            };
            deps.runtime
                .run_job_as(user_id.as_str(), worker_id, || {
                    worker.process(&job, worker_id, &bytes)
                })
                .await
        }
    };

    handle_job_result(deps, result, worker_id, job.id).await
}

/// One schedule-worker poll. See [`script_worker_tick`] for the rationale.
async fn schedule_worker_tick(
    deps: &WorkerDeps,
    worker_id: &str,
    shutdown: &mut ShutdownSignal,
) -> Result<(), DomainError> {
    let (job, released) = match deps
        .queue
        .claim_next_kind_reconciling(worker_id, DocumentKind::Schedule)
        .await?
    {
        Some(pair) => pair,
        None => {
            tokio::select! {
                _ = shutdown.changed() => {}
                _ = tokio::time::sleep(EMPTY_QUEUE_SLEEP) => {}
            }
            return Ok(());
        }
    };

    if released.is_some() {
        info!(
            worker_id,
            job_id = %job.id.as_uuid(),
            "reclaimed orphaned schedule job"
        );
    }

    // Start a claim heartbeat before source loading (issue #214). A slow or
    // hung load of a large PDF must not outlive the claim lease: another
    // worker could otherwise reclaim the job while this one is still loading.
    // Mirrors the protection the existing `run_once_with_permit` workers apply
    // in `workers.rs`.
    let heartbeat = deps
        .queue
        .lease_window()
        .and_then(|lease| LeaseHeartbeat::start(deps.queue.clone(), job.id, worker_id, lease));

    let bytes = match deps.source.load(&job.source_handle).await {
        Ok(bytes) => bytes,
        Err(error) => {
            if let Some(heartbeat) = heartbeat {
                heartbeat.stop();
            }
            warn!(
                worker_id,
                job_id = %job.id.as_uuid(),
                %error,
                "failed to load schedule source; failing job"
            );
            super::workers::fail_payload_load(&*deps.queue, job.id, worker_id, &error).await?;
            return Ok(());
        }
    };

    if claim_lost(heartbeat.as_ref()) {
        // Another worker owns the job now; every terminal write of ours would be
        // rejected, so stop before any further work.
        return Err(DomainError::Conflict(format!(
            "AI import job {} was reclaimed while its source loaded",
            job.id.as_uuid()
        )));
    }
    if let Some(heartbeat) = heartbeat {
        heartbeat.stop();
    }

    let user_id = job.user_id.clone();
    let config = match resolve_config(&deps.config_repo, &user_id, DocumentKind::Schedule).await {
        Ok(config) => config,
        Err(error) => {
            warn!(
                worker_id,
                job_id = %job.id.as_uuid(),
                %error,
                "failed to resolve AI config; failing job"
            );
            deps.queue
                .mark_failed(
                    job.id,
                    worker_id,
                    &error.to_string(),
                    matches!(error, DomainError::ServiceUnavailable(_)),
                )
                .await?;
            return Ok(());
        }
    };

    // Fetch the API key only for OpenAI-compatible providers. Ollama needs no
    // bearer token (its base URL is plain HTTP), so fetching one would issue
    // an unnecessary Vault request (issue #214).
    let api_key = match config.provider {
        LlmProvider::Ollama => String::new(),
        _ => match fetch_api_key(&*deps.credentials, &config).await {
            Ok(key) => key,
            Err(error) => {
                warn!(
                    worker_id,
                    job_id = %job.id.as_uuid(),
                    %error,
                    "failed to fetch AI credential; failing job"
                );
                deps.queue
                    .mark_failed(
                        job.id,
                        worker_id,
                        &error.to_string(),
                        matches!(error, DomainError::ServiceUnavailable(_)),
                    )
                    .await?;
                return Ok(());
            }
        },
    };

    let result = match config.provider {
        LlmProvider::Ollama => {
            let client =
                match build_ollama_client(Duration::from_secs(deps.bounds.request_timeout_secs)) {
                    Ok(client) => client,
                    Err(error) => {
                        warn!(
                            worker_id,
                            job_id = %job.id.as_uuid(),
                            %error,
                            "failed to build Ollama client; failing job"
                        );
                        deps.queue
                            .mark_failed(job.id, worker_id, &error.to_string(), false)
                            .await?;
                        return Ok(());
                    }
                };
            let worker = ScheduleImportWorker {
                queue: deps.queue.clone(),
                client,
                previews: deps.previews.clone(),
                extractor: PdfTextExtractor::new(
                    usize::try_from(deps.bounds.max_document_bytes).unwrap_or(usize::MAX),
                    Duration::from_secs(deps.bounds.request_timeout_secs),
                ),
                provider: config.provider,
                model: config.model,
                prompt: config.prompt,
                bounds: deps.bounds,
            };
            deps.runtime
                .run_job_as(user_id.as_str(), worker_id, || {
                    worker.process(&job, worker_id, &bytes)
                })
                .await
        }
        _ => {
            let client = match build_openai_client(
                config.provider,
                api_key,
                Duration::from_secs(deps.bounds.request_timeout_secs),
            )
            .await
            {
                Ok(client) => client,
                Err(error) => {
                    warn!(
                        worker_id,
                        job_id = %job.id.as_uuid(),
                        %error,
                        "failed to build LLM client; failing job"
                    );
                    deps.queue
                        .mark_failed(job.id, worker_id, &error.to_string(), false)
                        .await?;
                    return Ok(());
                }
            };
            let worker = ScheduleImportWorker {
                queue: deps.queue.clone(),
                client,
                previews: deps.previews.clone(),
                extractor: PdfTextExtractor::new(
                    usize::try_from(deps.bounds.max_document_bytes).unwrap_or(usize::MAX),
                    Duration::from_secs(deps.bounds.request_timeout_secs),
                ),
                provider: config.provider,
                model: config.model,
                prompt: config.prompt,
                bounds: deps.bounds,
            };
            deps.runtime
                .run_job_as(user_id.as_str(), worker_id, || {
                    worker.process(&job, worker_id, &bytes)
                })
                .await
        }
    };

    handle_job_result(deps, result, worker_id, job.id).await
}

/// Handle the result of a job run under a concurrency permit.
///
/// `Ok(None)` means the ceiling was saturated — hand the claim back so the job
/// is runnable immediately and is not charged a retry. Any other outcome is
/// returned as-is. Shared by both worker ticks, which otherwise duplicate this
/// block (issue #214).
async fn handle_job_result(
    deps: &WorkerDeps,
    result: Result<Option<String>, DomainError>,
    worker_id: &str,
    job_id: AiImportJobId,
) -> Result<(), DomainError> {
    match result {
        Ok(Some(_)) => Ok(()),
        Ok(None) => {
            warn!(
                worker_id,
                job_id = %job_id.as_uuid(),
                "AI import capacity saturated; returning the claim unrun"
            );
            if let Err(error) = deps.queue.release_claim(job_id, worker_id).await {
                warn!(
                    worker_id,
                    job_id = %job_id.as_uuid(),
                    %error,
                    "failed to release claim"
                );
            }
            Ok(())
        }
        Err(error) => Err(error),
    }
}
