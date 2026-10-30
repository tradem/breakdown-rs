// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use super::{DocumentKind, SourceFormat, TelemetryApplyState};

// ===========================================================================
// SourceFormat tests
// ===========================================================================

#[test]
fn only_csv_uses_the_native_parser() {
    assert!(SourceFormat::Csv.uses_native_csv());
    assert!(!SourceFormat::Pdf.uses_native_csv());
    assert!(!SourceFormat::PlainText.uses_native_csv());
}

#[test]
fn as_str_matches_the_database_check_constraint_values() {
    for (format, text) in [
        (SourceFormat::Csv, "csv"),
        (SourceFormat::Pdf, "pdf"),
        (SourceFormat::PlainText, "plain_text"),
    ] {
        assert_eq!(format.as_str(), text);
    }
}

// ===========================================================================
// P3.4 — DocumentKind::as_str (kills return "" / "xyzzy")
// ===========================================================================

#[test]
fn document_kind_as_str_script() {
    assert_eq!(DocumentKind::Script.as_str(), "script");
}

#[test]
fn document_kind_as_str_schedule() {
    assert_eq!(DocumentKind::Schedule.as_str(), "schedule");
}

#[test]
fn document_kind_as_str_never_empty() {
    for kind in [DocumentKind::Script, DocumentKind::Schedule] {
        assert!(!kind.as_str().is_empty(), "{kind:?} returns empty");
    }
}

// ===========================================================================
// P3.4 — TelemetryApplyState::accept_as_is (kills None / Some(false) / Some(true))
// ===========================================================================

#[test]
fn accept_as_is_not_applied_returns_none() {
    assert_eq!(TelemetryApplyState::NotApplied.accept_as_is(), None);
}

#[test]
fn accept_as_is_applied_true_returns_some_true() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: true,
        edit_distance: 0,
    };
    assert_eq!(state.accept_as_is(), Some(true));
}

#[test]
fn accept_as_is_applied_false_returns_some_false() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: false,
        edit_distance: 5,
    };
    assert_eq!(state.accept_as_is(), Some(false));
}

// ===========================================================================
// P3.4 — TelemetryApplyState::edit_distance (kills None / Some(0) / Some(1))
// ===========================================================================

#[test]
fn edit_distance_not_applied_returns_none() {
    assert_eq!(TelemetryApplyState::NotApplied.edit_distance(), None);
}

#[test]
fn edit_distance_applied_zero_returns_some_zero() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: true,
        edit_distance: 0,
    };
    assert_eq!(state.edit_distance(), Some(0));
}

#[test]
fn edit_distance_applied_nonzero_returns_correct_value() {
    let state = TelemetryApplyState::Applied {
        accept_as_is: false,
        edit_distance: 42,
    };
    assert_eq!(state.edit_distance(), Some(42));
}

// ===========================================================================
// TelemetryApplyState default
// ===========================================================================

#[test]
fn telemetry_apply_state_default_is_not_applied() {
    assert_eq!(
        TelemetryApplyState::default(),
        TelemetryApplyState::NotApplied
    );
}

// ===========================================================================
// JobStatus::as_str
// ===========================================================================

#[test]
fn job_status_as_str_matches_variant() {
    assert_eq!(super::JobStatus::Pending.as_str(), "pending");
    assert_eq!(super::JobStatus::Running.as_str(), "running");
    assert_eq!(super::JobStatus::Succeeded.as_str(), "succeeded");
    assert_eq!(super::JobStatus::Failed.as_str(), "failed");
    assert_eq!(super::JobStatus::DeadLetter.as_str(), "dead_letter");
    assert_eq!(
        super::JobStatus::PayloadUnavailable.as_str(),
        "payload_unavailable"
    );
}

// ===========================================================================
// JobStatus::is_terminal
// ===========================================================================

#[test]
fn succeeded_is_terminal() {
    assert!(super::JobStatus::Succeeded.is_terminal());
}

#[test]
fn dead_letter_is_terminal() {
    assert!(super::JobStatus::DeadLetter.is_terminal());
}

#[test]
fn payload_unavailable_is_terminal() {
    assert!(super::JobStatus::PayloadUnavailable.is_terminal());
}

#[test]
fn pending_is_not_terminal() {
    assert!(!super::JobStatus::Pending.is_terminal());
}

#[test]
fn running_is_not_terminal() {
    assert!(!super::JobStatus::Running.is_terminal());
}

#[test]
fn failed_is_not_terminal() {
    assert!(!super::JobStatus::Failed.is_terminal());
}

// ===========================================================================
// JobStatus::is_non_resumable
// ===========================================================================

#[test]
fn payload_unavailable_is_non_resumable() {
    assert!(super::JobStatus::PayloadUnavailable.is_non_resumable());
}

#[test]
fn dead_letter_is_resumable() {
    // DeadLetter is terminal but not non-resumable; only PayloadUnavailable is non-resumable
    assert!(!super::JobStatus::DeadLetter.is_non_resumable());
}

#[test]
fn failed_is_resumable() {
    assert!(!super::JobStatus::Failed.is_non_resumable());
}

// ===========================================================================
// AiImportStage / AiImportProgress — job progress view (issue #664)
// ===========================================================================

use super::{AiImportProgress, AiImportStage, DraftEpisode};

#[test]
fn ai_import_stage_as_str_matches_the_wire_snake_case() {
    for (stage, text) in [
        (AiImportStage::ExtractingText, "extracting_text"),
        (AiImportStage::Extracting, "extracting"),
        (AiImportStage::Merging, "merging"),
        (AiImportStage::StoringPreview, "storing_preview"),
    ] {
        assert_eq!(stage.as_str(), text);
        assert_eq!(
            serde_json::to_value(stage)
                .ok()
                .and_then(|v| v.as_str().map(str::to_owned)),
            Some(text.to_owned())
        );
    }
}

#[test]
fn ai_import_progress_default_is_extracting_text_without_counts() {
    let progress = AiImportProgress::default();
    assert_eq!(progress.stage, AiImportStage::ExtractingText);
    assert_eq!(progress.chunk, None);
    assert_eq!(progress.chunks_total, None);
    assert!(progress.episodes_seen.is_empty());
}

#[test]
fn record_episode_appends_labels_in_first_seen_order() {
    let mut progress = AiImportProgress::default();
    progress.record_episode(Some(&DraftEpisode {
        number: Some(3),
        title: None,
    }));
    progress.record_episode(Some(&DraftEpisode {
        number: Some(4),
        title: None,
    }));
    assert_eq!(
        progress.episodes_seen,
        vec!["Ep. 3".to_owned(), "Ep. 4".to_owned()]
    );
}

#[test]
fn record_episode_deduplicates_repeated_markers() {
    let mut progress = AiImportProgress::default();
    let episode = DraftEpisode {
        number: Some(3),
        title: None,
    };
    // Page headers repeat the marker on every chunk — it stays a single entry.
    for _ in 0..3 {
        progress.record_episode(Some(&episode));
    }
    assert_eq!(progress.episodes_seen, vec!["Ep. 3".to_owned()]);
}

#[test]
fn record_episode_ignores_episodes_without_a_label() {
    let mut progress = AiImportProgress::default();
    progress.record_episode(None);
    progress.record_episode(Some(&DraftEpisode {
        number: None,
        title: Some("   ".into()),
    }));
    assert!(progress.episodes_seen.is_empty());
}

/// Issue #767: the job-level decision outcome is additive in BOTH directions —
/// a pre-#767 payload (no field) still deserializes, and a recorded outcome
/// serializes with the stable snake_case outcome classes a client branches on.
#[test]
fn ai_import_job_decision_telemetry_is_additive_on_the_wire() {
    let job: super::AiImportJob = serde_json::from_str(
        r#"{
            "id": "01950000-0000-7000-8000-000000000002",
            "user_id": "user-1",
            "document_kind": "script",
            "source_format": "pdf",
            "dedup_key": "k",
            "document_digest": "d",
            "source_handle": "h",
            "status": "succeeded",
            "retries": 0,
            "max_retries": 5,
            "created_at": "2026-11-02T00:00:00Z",
            "updated_at": "2026-11-02T00:00:00Z"
        }"#,
    )
    .expect("a pre-#767 payload deserializes");
    assert_eq!(job.decision_telemetry, None);

    let recorded = super::DecisionTelemetry {
        provider: Some(super::LlmProvider::Neuralwatt),
        model: Some("glm-5.3".to_owned()),
        outcome: super::DecisionOutcome::ScoringFailed,
        failed_rows: 3,
    };
    let json = serde_json::to_value(&recorded).expect("serializes");
    assert_eq!(json["outcome"], "scoring_failed");
    assert_eq!(json["failed_rows"], 3);
    assert_eq!(
        serde_json::from_value::<super::DecisionTelemetry>(json).ok(),
        Some(recorded),
        "the recorded outcome round-trips"
    );

    // A "nothing was configured" outcome names no provider/model at all: the
    // optional fields stay absent instead of serializing a null pair.
    let unconfigured = super::DecisionTelemetry {
        provider: None,
        model: None,
        outcome: super::DecisionOutcome::SkippedNoConfig,
        failed_rows: 0,
    };
    let json = serde_json::to_value(&unconfigured).expect("serializes");
    assert_eq!(json["outcome"], "skipped_no_config");
    assert!(json.get("provider").is_none());
    assert!(json.get("model").is_none());
}

#[test]
fn ai_import_job_progress_is_optional_on_the_wire() {
    // An older payload without `progress` deserializes to `None` (additive).
    let job: super::AiImportJob = serde_json::from_str(
        r#"{
            "id": "01950000-0000-7000-8000-000000000001",
            "user_id": "user-1",
            "document_kind": "script",
            "source_format": "pdf",
            "dedup_key": "k",
            "document_digest": "d",
            "source_handle": "h",
            "status": "running",
            "retries": 0,
            "max_retries": 5,
            "created_at": "2026-10-12T00:00:00Z",
            "updated_at": "2026-10-12T00:00:00Z"
        }"#,
    )
    .expect("test fixture deserializes");
    assert_eq!(job.progress, None);

    let with_progress = AiImportProgress {
        stage: AiImportStage::Extracting,
        chunk: Some(4),
        chunks_total: Some(12),
        episodes_seen: vec!["Ep. 3".to_owned(), "Ep. 4".to_owned()],
    };
    let json = serde_json::to_value(&with_progress).ok();
    assert_eq!(
        json.map(|v| v["stage"].as_str().map(str::to_owned)),
        Some(Some("extracting".to_owned()))
    );
}
