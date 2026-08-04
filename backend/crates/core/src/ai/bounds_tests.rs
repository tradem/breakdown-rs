// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use super::AiImportBounds;

#[test]
fn worst_case_token_budget_is_derived_without_sleeping() {
    let bounds = AiImportBounds::default();
    assert_eq!(
        bounds.worst_case_tokens(),
        u64::from(bounds.max_chunks_per_script) * u64::from(bounds.max_tokens_per_req)
    );
    assert!(bounds.worst_case_tokens() > 0);
    assert!(bounds.validate().is_ok());
}

#[test]
fn per_user_concurrency_cannot_exceed_global() {
    let invalid = AiImportBounds {
        max_concurrent_jobs_global: 1,
        max_concurrent_jobs_per_user: 2,
        ..AiImportBounds::default()
    };
    assert!(invalid.validate().is_err());
}
