// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Resume-cursor and wire-contract tests (issue #871, tasks 4.3).

use crate::ai::ports::{LlmCallUsage, StoredChunk, resume_cursor};
use crate::ai::preview::ScriptContext;

fn chunk(index: u32) -> StoredChunk {
    StoredChunk {
        chunk_index: index,
        payload: ScriptContext::default(),
        usage: LlmCallUsage::default(),
    }
}

#[test]
fn an_empty_store_resumes_at_zero() {
    assert_eq!(resume_cursor(&[]), 0);
}

#[test]
fn a_contiguous_prefix_is_its_length() {
    assert_eq!(resume_cursor(&[chunk(0)]), 1);
    assert_eq!(resume_cursor(&[chunk(0), chunk(1), chunk(2)]), 3);
}

#[test]
fn a_hole_ends_the_cursor_at_the_hole() {
    // `0, 1, 3` must answer 2 — NOT 4. `MAX + 1` would resume past the missing
    // chunk 2 and silently omit it from the preview (D-B2).
    let chunks = [chunk(0), chunk(1), chunk(3)];
    assert_eq!(resume_cursor(&chunks), 2);
    assert_ne!(resume_cursor(&chunks), 4);
}

#[test]
fn a_store_that_does_not_start_at_zero_resumes_at_zero() {
    // A tail beyond a hole is deleted by the store, but the cursor must be
    // correct even if such rows ever reach it.
    assert_eq!(resume_cursor(&[chunk(1), chunk(2)]), 0);
}

#[test]
fn the_cursor_is_the_prefix_length_for_a_full_run() {
    let chunks: Vec<StoredChunk> = (0..42).map(chunk).collect();
    assert_eq!(resume_cursor(&chunks), 42);
}

#[test]
fn resumed_from_round_trips_and_absence_is_none() {
    use crate::ai::AiImportProgress;

    let mut progress = AiImportProgress::default();
    assert_eq!(progress.resumed_from, None);
    progress.resumed_from = Some(25);
    let json = serde_json::to_string(&progress).unwrap_or_default();
    assert!(json.contains("\"resumed_from\":25"));
    let back: AiImportProgress = serde_json::from_str(&json).unwrap_or_default();
    assert_eq!(back.resumed_from, Some(25));

    // A pre-#871 frame carries no such key and must decode as `None` — the
    // estimate then behaves exactly as before, never a fabricated basis.
    let legacy: AiImportProgress =
        serde_json::from_str(r#"{"stage":"extracting","chunk":7}"#).unwrap_or_default();
    assert_eq!(legacy.resumed_from, None);
    assert_eq!(legacy.chunk, Some(7));
}
