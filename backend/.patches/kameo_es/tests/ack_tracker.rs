// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Deterministic tests for the patched kameo_es event-handler
//! acknowledgement contract (issue #165): the SierraDB cursor advances only
//! after successful event processing — a failed event never becomes the
//! acknowledged cursor.

use kameo_es::event_handler::AckTracker;

#[test]
fn ack_fires_at_batch_boundary_with_the_processed_cursor() {
    let mut ack = AckTracker::default();
    for cursor in 1..AckTracker::BATCH_SIZE {
        assert_eq!(ack.processed(cursor), None);
    }
    // The 8000th processed event triggers the batch ack at its own cursor.
    assert_eq!(
        ack.processed(AckTracker::BATCH_SIZE),
        Some(AckTracker::BATCH_SIZE)
    );
    // Counter resets: the next event does not immediately trigger an ack.
    assert_eq!(ack.processed(AckTracker::BATCH_SIZE + 1), None);
}

#[test]
fn a_failed_event_never_becomes_the_ack_cursor() {
    let mut ack = AckTracker::default();
    for cursor in 1..AckTracker::BATCH_SIZE {
        assert_eq!(ack.processed(cursor), None);
    }
    // The event at BATCH_SIZE fails: `processed` is NOT called for it (the
    // handler returned an error and the run loop aborts), so the ack
    // boundary is not reached. The next successful event triggers the ack at
    // ITS OWN cursor — the acked cursor always corresponds to a successfully
    // processed event.
    let acked = ack
        .processed(AckTracker::BATCH_SIZE + 1)
        .expect("boundary reached after the next successful event");
    assert_eq!(acked, AckTracker::BATCH_SIZE + 1);
}
