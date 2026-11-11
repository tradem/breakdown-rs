// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use uuid::Uuid;

use super::{
    AggregateVersion, AiImportMapping, CURATED_PROVIDERS, DocumentKind, LlmCallUsage, LlmProvider,
    UsageAccumulator,
};

// ===========================================================================
// P3.3 — LlmClient-Port-Defaults
// ===========================================================================

// --- LlmProvider::as_str (kills return "" / "xyzzy") ---------------------

#[test]
fn llm_provider_as_str_matches_variant_name() {
    assert_eq!(LlmProvider::OpenAI.as_str(), "openai");
    assert_eq!(LlmProvider::Gemini.as_str(), "gemini");
    assert_eq!(LlmProvider::OpenRouter.as_str(), "openrouter");
    assert_eq!(LlmProvider::EURouter.as_str(), "eurouter");
    assert_eq!(LlmProvider::Neuralwatt.as_str(), "neuralwatt");
    assert_eq!(LlmProvider::OpenCodeGo.as_str(), "opencode-go");
    assert_eq!(LlmProvider::OpenCode.as_str(), "opencode");
    assert_eq!(LlmProvider::Ollama.as_str(), "ollama");
}

#[test]
fn llm_provider_as_str_never_empty() {
    for provider in CURATED_PROVIDERS {
        assert!(!provider.as_str().is_empty(), "{provider:?} returns empty");
    }
}

#[test]
fn llm_provider_as_str_never_xyzzy() {
    for provider in CURATED_PROVIDERS {
        assert_ne!(
            provider.as_str(),
            "xyzzy",
            "{provider:?} returns wrong value"
        );
    }
}

// --- LlmProvider::Gemini wire keys (issue #675) ---------------------------

#[test]
fn gemini_serializes_as_canonical_key() {
    assert_eq!(
        serde_json::to_string(&LlmProvider::Gemini).unwrap(),
        "\"gemini\""
    );
}

#[test]
fn gemini_deserializes_from_canonical_and_google_alias() {
    assert_eq!(
        serde_json::from_str::<LlmProvider>("\"gemini\"").unwrap(),
        LlmProvider::Gemini
    );
    assert_eq!(
        serde_json::from_str::<LlmProvider>("\"google\"").unwrap(),
        LlmProvider::Gemini
    );
}

#[test]
fn gemini_is_not_local() {
    assert!(!LlmProvider::Gemini.is_local());
}

// --- LlmProvider::curated_base_url_key (kills return "" / "xyzzy") --------

#[test]
fn llm_provider_curated_base_url_key_matches_as_str() {
    for provider in CURATED_PROVIDERS {
        assert_eq!(
            provider.curated_base_url_key(),
            provider.as_str(),
            "curated_base_url_key should match as_str for {provider:?}"
        );
    }
}

// --- LlmProvider::is_local (kills return false / true) --------------------

#[test]
fn only_ollama_is_local() {
    for provider in CURATED_PROVIDERS {
        let expected = provider == LlmProvider::Ollama;
        assert_eq!(
            provider.is_local(),
            expected,
            "{provider:?}.is_local() should be {expected}"
        );
    }
}

#[test]
fn openai_is_not_local() {
    assert!(!LlmProvider::OpenAI.is_local());
}

#[test]
fn ollama_is_local() {
    assert!(LlmProvider::Ollama.is_local());
}

// --- AiImportMapping::is_reserved (kills == → !=, return false/true) ------

#[test]
fn mapping_is_reserved_when_version_is_zero() {
    let mapping = AiImportMapping {
        preview_id: super::AiImportJobId::new(),
        draft_ref: "scene-1".into(),
        aggregate_kind: "scene".into(),
        ordinal: super::PRIMARY_ORDINAL,
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion(0),
    };
    assert!(
        mapping.is_reserved(),
        "RESERVED_VERSION (0) should be reserved"
    );
}

#[test]
fn mapping_is_not_reserved_after_confirmation() {
    let mapping = AiImportMapping {
        preview_id: super::AiImportJobId::new(),
        draft_ref: "scene-1".into(),
        aggregate_kind: "scene".into(),
        ordinal: super::PRIMARY_ORDINAL,
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion::INITIAL,
    };
    assert!(
        !mapping.is_reserved(),
        "non-zero version should not be reserved"
    );
}

#[test]
fn mapping_is_not_reserved_for_high_version() {
    let mapping = AiImportMapping {
        preview_id: super::AiImportJobId::new(),
        draft_ref: "scene-1".into(),
        aggregate_kind: "scene".into(),
        ordinal: super::PRIMARY_ORDINAL,
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion(999),
    };
    assert!(!mapping.is_reserved());
}

#[test]
fn mapping_reservation_creates_reserved_mapping() {
    let preview_id = super::AiImportJobId::new();
    let aggregate_id = Uuid::now_v7();
    let mapping = AiImportMapping::reservation(
        preview_id,
        "scene-1".into(),
        super::mapping_kind::SCENE.into(),
        super::PRIMARY_ORDINAL,
        aggregate_id,
    );
    assert!(mapping.is_reserved());
    assert_eq!(mapping.aggregate_id, aggregate_id);
    assert_eq!(mapping.ordinal, super::PRIMARY_ORDINAL);
    assert_eq!(mapping.aggregate_version, AggregateVersion(0));
}

#[test]
fn mapping_kinds_are_the_discriminators_of_one_rows_mapping_key() {
    // One draft row produces a scene row, figure rows, piece rows, outfit rows
    // and beat rows that all share its `draft_ref`; only (kind, ordinal) tells
    // them apart, so the constants must stay distinct strings.
    let kinds = [
        super::mapping_kind::SCENE,
        super::mapping_kind::CHARACTER,
        super::mapping_kind::PIECE,
        super::mapping_kind::OUTFIT,
        super::mapping_kind::SHOOTING_DAY,
        super::mapping_kind::SCENE_SHOOT,
        super::mapping_kind::SCENE_OUTFIT_BEAT,
        super::mapping_kind::EPISODE,
    ];
    let unique: std::collections::HashSet<&str> = kinds.iter().copied().collect();
    assert_eq!(unique.len(), kinds.len(), "kinds must not collide");
}

// --- CURATED_PROVIDERS constant -------------------------------------------

#[test]
fn curated_providers_has_eight_entries() {
    assert_eq!(CURATED_PROVIDERS.len(), 8);
}

#[test]
fn curated_providers_contains_all_variants() {
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenAI));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::Gemini));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenRouter));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::EURouter));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::Neuralwatt));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenCodeGo));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::OpenCode));
    assert!(CURATED_PROVIDERS.contains(&LlmProvider::Ollama));
}

// --- DocumentKind::as_str (kills return "" / "xyzzy") ---------------------

#[test]
fn document_kind_as_str_matches_variant() {
    assert_eq!(DocumentKind::Script.as_str(), "script");
    assert_eq!(DocumentKind::Schedule.as_str(), "schedule");
}

// --- AiImportMapping::RESERVED_VERSION ------------------------------------

#[test]
fn reserved_version_is_zero() {
    assert_eq!(AiImportMapping::RESERVED_VERSION, AggregateVersion(0));
}

// --- UsageAccumulator: a zero-usage call is still a call (issue #768) -----

#[test]
fn a_zero_usage_call_is_counted_as_a_call() {
    // A provider may answer without any usage metadata. The counters stay 0,
    // but the call happened — the cost snapshot must not treat it as absent.
    let mut accumulator = UsageAccumulator::default();
    accumulator.record(LlmCallUsage::default());
    assert_eq!(accumulator.usage, LlmCallUsage::default());
    assert_eq!(accumulator.calls, 1);
}

#[test]
fn recorded_calls_accumulate_element_wise() {
    let mut accumulator = UsageAccumulator::default();
    accumulator.record(LlmCallUsage {
        tokens_in: 10,
        tokens_out: 2,
        cached_tokens_in: 1,
        energy_millijoules: 5,
    });
    accumulator.record(LlmCallUsage {
        tokens_in: 3,
        tokens_out: 1,
        cached_tokens_in: 0,
        energy_millijoules: 2,
    });
    assert_eq!(
        accumulator.usage,
        LlmCallUsage {
            tokens_in: 13,
            tokens_out: 3,
            cached_tokens_in: 1,
            energy_millijoules: 7,
        }
    );
    assert_eq!(accumulator.calls, 2);
}

#[test]
fn recorded_calls_are_retained_for_per_request_pricing() {
    // Issue #794: a provider caps energy per request, so the ledger has to
    // survive accumulation — the summed counters cannot be re-split.
    let mut accumulator = UsageAccumulator::default();
    let first = LlmCallUsage {
        tokens_in: 10,
        ..Default::default()
    };
    let second = LlmCallUsage {
        tokens_in: 1,
        energy_millijoules: 18_000,
        ..Default::default()
    };
    accumulator.record(first);
    accumulator.record(second);
    assert_eq!(accumulator.per_call, vec![first, second]);
    assert_eq!(accumulator.priced_calls(), &[first, second]);
}

#[test]
fn an_accumulator_without_a_ledger_prices_as_one_aggregate_request() {
    // A hand-built (or pre-#794 recorded) accumulator carries counters but no
    // ledger: it must still price — as the single aggregate request, which is
    // exactly the pre-#794 figure, never a zero.
    let aggregate = LlmCallUsage {
        tokens_in: 13,
        tokens_out: 3,
        cached_tokens_in: 1,
        energy_millijoules: 7,
    };
    let accumulator = UsageAccumulator {
        usage: aggregate,
        calls: 2,
        per_call: Vec::new(),
    };
    assert_eq!(accumulator.priced_calls(), &[aggregate]);
}

#[test]
fn the_call_count_saturates_instead_of_wrapping() {
    let mut accumulator = UsageAccumulator {
        usage: LlmCallUsage::default(),
        calls: u32::MAX,
        per_call: Vec::new(),
    };
    accumulator.record(LlmCallUsage::default());
    assert_eq!(accumulator.calls, u32::MAX);
}

// ===========================================================================
// Issue #800 review — the `apply_run_state` port default
// ===========================================================================

mod apply_run_state_default {
    use async_trait::async_trait;

    use super::super::{
        AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJob, AiImportJobId, AiImportQueue,
        ApplyProgress, ApplyRunId, DocumentKind, Telemetry,
    };
    // The view types are re-exported on `ai`, not on the port module.
    use crate::ai::{ApplyStage, JobStatus, SourceFormat};
    use crate::error::DomainError;
    use crate::shared::UserId;
    use chrono::Utc;

    /// A queue that implements only the REQUIRED methods, so `apply_run_state`,
    /// `claim_apply_run` and `mark_apply_progress` are the trait's defaults.
    struct DefaultOnlyQueue {
        job: Option<AiImportJob>,
    }

    #[async_trait]
    impl AiImportQueue for DefaultOnlyQueue {
        async fn enqueue(
            &self,
            _request: AiImportEnqueueRequest,
        ) -> Result<AiImportEnqueueResult, DomainError> {
            Err(unsupported())
        }

        async fn claim_next(&self, _worker_id: &str) -> Result<Option<AiImportJob>, DomainError> {
            Ok(None)
        }

        async fn claim_next_kind(
            &self,
            _worker_id: &str,
            _kind: DocumentKind,
        ) -> Result<Option<AiImportJob>, DomainError> {
            Ok(None)
        }

        async fn get(&self, _id: AiImportJobId) -> Result<Option<AiImportJob>, DomainError> {
            Ok(self.job.clone())
        }

        async fn mark_running(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
        ) -> Result<(), DomainError> {
            Err(unsupported())
        }

        async fn mark_succeeded(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _preview_handle: &str,
        ) -> Result<(), DomainError> {
            Err(unsupported())
        }

        async fn mark_failed(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _error_summary: &str,
            _error_code: Option<&str>,
            _retryable: bool,
        ) -> Result<(), DomainError> {
            Err(unsupported())
        }

        async fn record_worker_telemetry(
            &self,
            _id: AiImportJobId,
            _worker_id: &str,
            _telemetry: Telemetry,
        ) -> Result<(), DomainError> {
            Err(unsupported())
        }

        async fn record_telemetry(
            &self,
            _id: AiImportJobId,
            _telemetry: Telemetry,
        ) -> Result<(), DomainError> {
            Err(unsupported())
        }
    }

    fn unsupported() -> DomainError {
        DomainError::Internal {
            reason: "not tracked by the default-only test queue".to_owned(),
        }
    }

    fn progress(run_id: ApplyRunId) -> ApplyProgress {
        let now = Utc::now();
        ApplyProgress {
            stage: ApplyStage::Applying,
            applied: 3,
            total: 9,
            started_at: now,
            updated_at: now,
            run_id,
        }
    }

    fn job_with(payload: Option<ApplyProgress>) -> AiImportJob {
        AiImportJob {
            id: AiImportJobId::new(),
            user_id: UserId::from_sub("default-only"),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: "dedup".to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "source".to_owned(),
            source_file_name: None,
            target: None,
            // Issue #871: no provider snapshot and no hold on a pre-#871 row.
            provider: None,
            model: None,
            provider_hold: None,
            status: JobStatus::Succeeded,
            preview_handle: Some("preview".to_owned()),
            last_error: None,
            retries: 0,
            max_retries: 3,
            next_attempt_at: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            progress: None,
            attempts: Vec::new(),
            telemetry: None,
            cost: None,
            applied_episodes: Vec::new(),
            decision_telemetry: None,
            apply_progress: payload,
            applied: false,
        }
    }

    /// The default must MIRROR `get`, not answer `None`: the apply stream ends on
    /// `None`, so a default `None` would cut every such adapter's stream off
    /// after its snapshot frame — without the documented final `null` frame.
    #[test]
    fn the_default_reports_the_payload_it_published() {
        let run_id = ApplyRunId::new();
        let payload = progress(run_id);
        let job = job_with(Some(payload.clone()));
        let id = job.id;
        let queue = DefaultOnlyQueue { job: Some(job) };
        let state = futures::executor::block_on(queue.apply_run_state(id))
            .expect("the default reads the job")
            .expect("the job exists");
        assert_eq!(state.progress, Some(payload), "the payload is mirrored");
        assert_eq!(
            state.owner,
            Some(run_id),
            "and the owner is derived from the payload"
        );
        assert_eq!(state.seq, 0, "an adapter with no counter reports none");
    }

    /// No job → `None` (the stream closes), exactly like the pre-#800 contract.
    #[test]
    fn the_default_reports_no_slot_for_a_missing_job() {
        let queue = DefaultOnlyQueue { job: None };
        let state = futures::executor::block_on(queue.apply_run_state(AiImportJobId::new()))
            .expect("the default reads the job");
        assert!(state.is_none(), "an unknown job has no slot");
    }

    /// A job with no payload → an empty slot, so the stream keeps waiting
    /// instead of ending on a run that never published.
    #[test]
    fn the_default_reports_an_empty_slot_without_a_payload() {
        let job = job_with(None);
        let id = job.id;
        let queue = DefaultOnlyQueue { job: Some(job) };
        let state = futures::executor::block_on(queue.apply_run_state(id))
            .expect("the default reads the job")
            .expect("the job exists");
        assert_eq!(state.owner, None);
        assert_eq!(state.progress, None);
        assert_eq!(state.seq, 0);
        assert!(
            state.owner_claimed_at.is_none(),
            "a job DTO carries no claim instant, and the default must not \
             guess one from the row stamp (issue #863 review)"
        );
        assert_eq!(
            state.owner_silence_at(Utc::now()),
            None,
            "a slot with no owner has nothing to age"
        );
    }
}

// ===========================================================================
// Issue #863 — the ONE definition of the blocked run's age
// ===========================================================================

mod owner_silence {
    use super::super::{ApplyProgress, ApplyRunId, ApplyRunState};
    // The view types are re-exported on `ai`, not on the port module.
    use crate::ai::ApplyStage;
    use chrono::{Duration, Utc};

    fn payload(run_id: ApplyRunId, updated_at: chrono::DateTime<Utc>) -> ApplyProgress {
        ApplyProgress {
            stage: ApplyStage::Applying,
            applied: 0,
            total: 0,
            started_at: updated_at,
            updated_at,
            run_id,
        }
    }

    /// The published case is unchanged since #805: the payload's own stamp is
    /// the age, because that is the column the claim compares once a payload
    /// exists.
    #[test]
    fn a_published_payload_is_aged_by_its_own_stamp() {
        let run_id = ApplyRunId::new();
        let now = Utc::now();
        let state = ApplyRunState {
            owner: Some(run_id),
            seq: 1,
            progress: Some(payload(run_id, now - Duration::minutes(4))),
            // A younger claim instant must NOT shorten the payload's age: only
            // the payload's column is the claim's comparison for this state.
            owner_claimed_at: Some(now - Duration::seconds(5)),
        };
        assert_eq!(state.owner_silence_at(now), Some(Duration::minutes(4)));
    }

    /// The #863 fix: a run that claimed the slot and published nothing is aged
    /// by its own claim instant — the column the steal predicate reads for
    /// `apply_progress IS NULL`.
    #[test]
    fn a_claim_without_a_payload_is_aged_by_the_claim_stamp() {
        let now = Utc::now();
        let state = ApplyRunState {
            owner: Some(ApplyRunId::new()),
            seq: 1,
            progress: None,
            owner_claimed_at: Some(now - Duration::minutes(12)),
        };
        assert_eq!(
            state.owner_silence_at(now),
            Some(Duration::minutes(12)),
            "a dead run that never published now has an age past the window"
        );
    }

    /// No stamp anywhere → no age. `0` would claim "just wrote" for a run that
    /// reported nothing, and a pre-#863 claim must keep degrading honestly.
    #[test]
    fn no_stamp_degrades_to_no_age() {
        let now = Utc::now();
        let state = ApplyRunState {
            owner: Some(ApplyRunId::new()),
            seq: 1,
            progress: None,
            owner_claimed_at: None,
        };
        assert_eq!(state.owner_silence_at(now), None);
    }

    /// No owner means nothing to age — even a claim instant must not invent one.
    #[test]
    fn an_idle_slot_is_not_aged_by_the_claim_stamp() {
        let now = Utc::now();
        let state = ApplyRunState {
            owner: None,
            seq: 3,
            progress: None,
            owner_claimed_at: Some(now - Duration::minutes(30)),
        };
        assert_eq!(state.owner_silence_at(now), None);
    }

    /// A stamp in the future (clock skew between writer and reader) is clamped
    /// to zero instead of reporting a negative age.
    #[test]
    fn a_future_stamp_is_clamped_to_zero() {
        let now = Utc::now();
        let state = ApplyRunState {
            owner: Some(ApplyRunId::new()),
            seq: 1,
            progress: None,
            owner_claimed_at: Some(now + Duration::minutes(3)),
        };
        assert_eq!(state.owner_silence_at(now), Some(Duration::zero()));
    }
}
