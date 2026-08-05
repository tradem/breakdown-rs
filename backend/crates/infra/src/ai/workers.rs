// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::sync::Arc;
use std::time::Instant;

use anyhow::Error as AnyhowError;
use breakdown_core::ai::{
    AiImportBounds, AiImportJob, AiImportJobId, AiImportMapping, AiImportMappingRepository,
    AiImportQueue, ApplyMapping, ApplyMappingDecision, DocumentKind, LlmChatRequest, LlmClient,
    MergedPreview, ScriptContext, ShootingSchedule, Telemetry, ensure_merge_applyable,
    ensure_script_applyable, extract_scenes, merge_schedule_to_scenes,
};
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::{CreateScene, UpdateSceneDetails};
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::shared::{EpisodeId, SeriesId, UserId};
use serde_json::to_vec;
use uuid::Uuid;

use super::pdf::PdfTextExtractor;
use super::preview_store::{AiDocumentSource, AiPreviewStore};
use crate::photo::sagas::retry_transient_value;

/// Script import pipeline. It is deliberately independent of HTTP and can be
/// driven by a queue worker or deterministic integration tests.
pub struct ScriptImportWorker<Q, C, S> {
    pub queue: Arc<Q>,
    pub client: Arc<C>,
    pub previews: Arc<S>,
    pub extractor: PdfTextExtractor,
    pub provider: breakdown_core::ai::LlmProvider,
    pub model: String,
    pub prompt: String,
    pub bounds: AiImportBounds,
}

impl<Q, C, S> ScriptImportWorker<Q, C, S>
where
    Q: AiImportQueue + 'static,
    C: LlmClient + 'static,
    S: AiPreviewStore + 'static,
{
    pub async fn run_once(
        &self,
        worker_id: &str,
        source: &dyn AiDocumentSource,
    ) -> Result<bool, DomainError> {
        let Some(job) = self
            .queue
            .claim_next_kind(worker_id, DocumentKind::Script)
            .await?
        else {
            return Ok(false);
        };
        let bytes = match source.load(&job.source_handle).await {
            Ok(bytes) => bytes,
            Err(error) => {
                self.fail(job.id, &error).await?;
                return Err(error);
            }
        };
        self.process(&job, &bytes).await.map(|_| true)
    }

    pub async fn process(
        &self,
        job: &AiImportJob,
        pdf_bytes: &[u8],
    ) -> Result<String, DomainError> {
        if job.document_kind != DocumentKind::Script {
            return Err(DomainError::ValidationError(
                "script worker received a non-script job".to_owned(),
            ));
        }
        let text = self.extractor.extract(pdf_bytes).await?;
        self.process_text(job, &text).await
    }

    /// Process already extracted text. This seam keeps PDF subprocess tests
    /// separate from deterministic worker tests.
    pub async fn process_text(&self, job: &AiImportJob, text: &str) -> Result<String, DomainError> {
        let started = Instant::now();
        let chunks = extract_scenes(text);
        let chunk_count = u32::try_from(chunks.len()).map_err(|error| {
            DomainError::ValidationError(format!(
                "script chunk count exceeds telemetry range: {error}"
            ))
        })?;
        if let Err(error) = validate_chunk_count(chunks.len(), self.bounds.max_chunks_per_script) {
            self.fail(job.id, &error).await?;
            return Err(error);
        }
        if chunks.is_empty() {
            let error = DomainError::ValidationError(
                "script did not contain an INT./EXT. scene heading".to_owned(),
            );
            self.fail(job.id, &error).await?;
            return Err(error);
        }

        let mut context = ScriptContext::default();
        for chunk in chunks {
            let request = LlmChatRequest {
                provider: self.provider,
                model: self.model.clone(),
                prompt: self.prompt.clone(),
                source_text: format!("{}\n{}", chunk.heading, chunk.text),
                max_tokens: self.bounds.max_tokens_per_req,
                response_schema: None,
            };
            let partial = retry_chat(self.client.as_ref(), request).await;
            match partial {
                Ok(partial) => {
                    if context.title.is_none() {
                        context.title = partial.title;
                    }
                    context.scenes.extend(partial.scenes);
                    context.uncertainties.extend(partial.uncertainties);
                }
                Err(error) => {
                    self.fail(job.id, &error).await?;
                    return Err(error);
                }
            }
        }
        let payload = to_vec(&context).map_err(|error| {
            DomainError::ValidationError(format!("could not serialize script preview: {error}"))
        })?;
        let handle = self.previews.put(job.id, payload).await?;
        self.queue
            .record_telemetry(
                job.id,
                Telemetry {
                    provider: Some(self.provider),
                    model: Some(self.model.clone()),
                    doc_kind: Some(DocumentKind::Script),
                    chunk_count,
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    ..Telemetry::default()
                },
            )
            .await?;
        self.queue.mark_succeeded(job.id, &handle).await?;
        Ok(handle)
    }

    async fn fail(&self, id: AiImportJobId, error: &DomainError) -> Result<(), DomainError> {
        self.queue
            .mark_failed(
                id,
                &error.to_string(),
                matches!(error, DomainError::ServiceUnavailable(_)),
            )
            .await
    }
}

/// Schedule import pipeline. CSV is parsed natively; unstructured input can
/// be passed to an LLM client implementing `extract_schedule`.
pub struct ScheduleImportWorker<Q, C, S> {
    pub queue: Arc<Q>,
    pub client: Arc<C>,
    pub previews: Arc<S>,
    pub provider: breakdown_core::ai::LlmProvider,
    pub model: String,
    pub prompt: String,
    pub bounds: AiImportBounds,
}

impl<Q, C, S> ScheduleImportWorker<Q, C, S>
where
    Q: AiImportQueue + 'static,
    C: LlmClient + 'static,
    S: AiPreviewStore + 'static,
{
    pub async fn run_once(
        &self,
        worker_id: &str,
        source: &dyn AiDocumentSource,
        native_csv: bool,
    ) -> Result<bool, DomainError> {
        let Some(job) = self
            .queue
            .claim_next_kind(worker_id, DocumentKind::Schedule)
            .await?
        else {
            return Ok(false);
        };
        let bytes = match source.load(&job.source_handle).await {
            Ok(bytes) => bytes,
            Err(error) => {
                self.fail(job.id, &error).await?;
                return Err(error);
            }
        };
        self.process(&job, &bytes, native_csv).await.map(|_| true)
    }

    pub async fn process(
        &self,
        job: &AiImportJob,
        bytes: &[u8],
        native_csv: bool,
    ) -> Result<String, DomainError> {
        if job.document_kind != DocumentKind::Schedule {
            return Err(DomainError::ValidationError(
                "schedule worker received a non-schedule job".to_owned(),
            ));
        }
        let started = Instant::now();
        let mut schedule = if native_csv {
            super::csv_schedule::parse_schedule_csv(bytes)?
        } else {
            let source_text = String::from_utf8(bytes.to_vec()).map_err(|error| {
                DomainError::ValidationError(format!(
                    "schedule document is not UTF-8 text: {error}"
                ))
            })?;
            let request = LlmChatRequest {
                provider: self.provider,
                model: self.model.clone(),
                prompt: self.prompt.clone(),
                source_text,
                max_tokens: self.bounds.max_tokens_per_req,
                response_schema: None,
            };
            retry_schedule(self.client.as_ref(), request).await?
        };
        if schedule.block_id.is_none() {
            schedule.block_id = job.block_id;
        }
        let payload = to_vec(&schedule).map_err(|error| {
            DomainError::ValidationError(format!("could not serialize schedule preview: {error}"))
        })?;
        let handle = self.previews.put(job.id, payload).await?;
        self.queue
            .record_telemetry(
                job.id,
                Telemetry {
                    provider: (!native_csv).then_some(self.provider),
                    model: (!native_csv).then(|| self.model.clone()),
                    doc_kind: Some(DocumentKind::Schedule),
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    ..Telemetry::default()
                },
            )
            .await?;
        self.queue.mark_succeeded(job.id, &handle).await?;
        Ok(handle)
    }

    async fn fail(&self, id: AiImportJobId, error: &DomainError) -> Result<(), DomainError> {
        self.queue
            .mark_failed(
                id,
                &error.to_string(),
                matches!(error, DomainError::ServiceUnavailable(_)),
            )
            .await
    }
}

/// Deterministic merge operation. A zero-scene input is explicitly blocked so
/// schedules cannot be applied before the script has produced real scenes.
pub struct MergeWorker;

impl MergeWorker {
    pub fn merge(
        schedule: &ShootingSchedule,
        scenes: &[breakdown_core::scene::views::SceneView],
    ) -> Result<MergedPreview, DomainError> {
        if scenes.is_empty() {
            return Err(DomainError::Conflict(
                "merge is pending until the block has applied scenes".to_owned(),
            ));
        }
        Ok(merge_schedule_to_scenes(schedule, scenes))
    }

    pub fn validate_for_apply(preview: &MergedPreview) -> Result<(), DomainError> {
        ensure_merge_applyable(preview).map_err(|error| DomainError::Conflict(error.to_string()))
    }
}

/// Apply worker for reviewed script rows. Each row checks the persisted mapping
/// before dispatching, so a crash/retry cannot create a duplicate Scene.
pub struct ApplyWorker<C, M, Q> {
    pub scene_commands: Arc<C>,
    pub mappings: Arc<M>,
    pub queue: Arc<Q>,
}

impl<C, M, Q> ApplyWorker<C, M, Q>
where
    C: SceneCommands + 'static,
    M: AiImportMappingRepository + 'static,
    Q: AiImportQueue + 'static,
{
    pub async fn apply_script(
        &self,
        request: ApplyScriptRequest<'_>,
    ) -> Result<Vec<UuidVersion>, DomainError> {
        let ApplyScriptRequest {
            actor,
            preview_id,
            preview,
            decisions,
            episode_id,
            series_id,
            telemetry,
        } = request;
        ensure_script_applyable(preview)
            .map_err(|error| DomainError::Conflict(error.to_string()))?;
        let mut applied = Vec::with_capacity(preview.scenes.len());
        for (index, draft) in preview.scenes.iter().enumerate() {
            let draft_ref = if draft.draft_ref.is_empty() {
                format!("scene-{index}")
            } else {
                draft.draft_ref.clone()
            };
            let stored = self.mappings.find(preview_id, &draft_ref).await?;
            let decision = stored
                .map(|mapping| ApplyMappingDecision::Update {
                    aggregate_id: mapping.aggregate_id,
                    version: mapping.aggregate_version,
                })
                .or_else(|| {
                    decisions
                        .iter()
                        .find(|decision| decision.draft_ref == draft_ref)
                        .map(|decision| decision.decision.clone())
                })
                .ok_or_else(|| {
                    DomainError::ValidationError(format!("missing mapping for {draft_ref}"))
                })?;
            let details = draft.scene_details();
            let (aggregate_id, version) = match decision {
                ApplyMappingDecision::Create => {
                    let (id, version) = self
                        .scene_commands
                        .create(
                            actor.clone(),
                            CreateScene {
                                id: Uuid::now_v7(),
                                episode_id,
                                series_id,
                                details,
                            },
                        )
                        .await?;
                    (id, version)
                }
                ApplyMappingDecision::Update {
                    aggregate_id,
                    version,
                } => {
                    let new_version = self
                        .scene_commands
                        .update_details(
                            actor.clone(),
                            UpdateSceneDetails {
                                id: aggregate_id,
                                details,
                                series_id,
                                version,
                            },
                        )
                        .await?;
                    (aggregate_id, new_version)
                }
            };
            self.mappings
                .insert(AiImportMapping {
                    preview_id,
                    draft_ref,
                    aggregate_kind: "scene".to_owned(),
                    aggregate_id,
                    aggregate_version: version,
                })
                .await?;
            applied.push(UuidVersion {
                aggregate_id,
                version,
            });
        }
        if let Some(telemetry) = telemetry {
            self.queue.record_telemetry(preview_id, telemetry).await?;
        }
        Ok(applied)
    }
}

pub struct ApplyScriptRequest<'a> {
    pub actor: UserId,
    pub preview_id: AiImportJobId,
    pub preview: &'a ScriptContext,
    pub decisions: &'a [ApplyMapping],
    pub episode_id: EpisodeId,
    pub series_id: Option<SeriesId>,
    pub telemetry: Option<Telemetry>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UuidVersion {
    pub aggregate_id: uuid::Uuid,
    pub version: breakdown_core::shared::AggregateVersion,
}

pub fn validate_chunk_count(chunk_count: usize, max_chunks: u32) -> Result<(), DomainError> {
    if chunk_count > max_chunks as usize {
        return Err(DomainError::ValidationError(format!(
            "script contains {chunk_count} chunks, exceeding max_chunks_per_script {max_chunks}"
        )));
    }
    Ok(())
}

async fn retry_chat<C>(client: &C, request: LlmChatRequest) -> Result<ScriptContext, DomainError>
where
    C: LlmClient + ?Sized,
{
    let outcome = retry_transient_value(|| async {
        client
            .chat_constrained(request.clone())
            .await
            .map_err(AnyhowError::new)
    })
    .await;
    match outcome {
        Ok(value) => Ok(value),
        Err(error) => match error.downcast::<DomainError>() {
            Ok(domain_error) => Err(domain_error),
            Err(other) => Err(DomainError::ValidationError(other.to_string())),
        },
    }
}

async fn retry_schedule<C>(
    client: &C,
    request: LlmChatRequest,
) -> Result<ShootingSchedule, DomainError>
where
    C: LlmClient + ?Sized,
{
    let outcome = retry_transient_value(|| async {
        client
            .extract_schedule(request.clone())
            .await
            .map_err(AnyhowError::new)
    })
    .await;
    match outcome {
        Ok(value) => Ok(value),
        Err(error) => match error.downcast::<DomainError>() {
            Ok(domain_error) => Err(domain_error),
            Err(other) => Err(DomainError::ValidationError(other.to_string())),
        },
    }
}
