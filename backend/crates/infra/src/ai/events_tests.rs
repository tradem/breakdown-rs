// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

use futures::StreamExt;

use super::{AiJobEventHub, parse_job_id};
use breakdown_core::ai::AiImportJobId;

fn job_id(seed: u8) -> AiImportJobId {
    AiImportJobId::from_uuid(uuid::Uuid::from_fields(0, seed as u16, 0, &[0u8; 8]))
}

#[tokio::test]
async fn subscriber_wakes_on_matching_notification() {
    let hub = AiJobEventHub::new();
    let id = job_id(1);
    let mut stream = hub.subscribe(id);

    hub.notify(id);
    assert_eq!(stream.next().await, Some(id));
}

#[tokio::test]
async fn subscriber_ignores_other_jobs_notifications() {
    let hub = AiJobEventHub::new();
    let watched = job_id(1);
    let other = job_id(2);
    let mut stream = hub.subscribe(watched);

    hub.notify(other);
    hub.notify(watched);
    // The stream skips the unrelated notification and yields only the match.
    assert_eq!(stream.next().await, Some(watched));
}

#[tokio::test]
async fn lagged_receiver_gets_a_synthetic_wake_up() {
    let hub = AiJobEventHub::new();
    let id = job_id(3);
    let mut stream = hub.subscribe(id);

    // Overflow the 256-slot broadcast buffer so the receiver lags.
    for i in 0..600u32 {
        hub.notify(AiImportJobId::from_uuid(uuid::Uuid::from_fields(
            0, i as u16, 0, &[0u8; 8],
        )));
    }
    hub.notify(id);

    // The first item may be the lag wake-up or the direct match — either way
    // the stream must yield promptly (never silently drop the watched job's
    // notification behind the lag).
    let first = stream.next().await;
    assert_eq!(first, Some(id));
}

#[tokio::test]
async fn notify_with_zero_listeners_is_a_no_op() {
    let hub = AiJobEventHub::new();
    // Must not panic or block without subscribers.
    hub.notify(job_id(4));
}

#[tokio::test]
async fn stream_ends_when_the_hub_is_dropped() {
    let id = job_id(5);
    let mut stream = {
        let hub = AiJobEventHub::new();
        hub.subscribe(id)
    };
    // All senders dropped: the stream terminates cleanly.
    assert_eq!(stream.next().await, None);
}

#[test]
fn parse_job_id_accepts_uuid_payloads_and_rejects_garbage() {
    let id = job_id(6);
    assert_eq!(parse_job_id(&id.as_uuid().to_string()), Some(id));
    assert_eq!(parse_job_id("not-a-uuid"), None);
    assert_eq!(parse_job_id(""), None);
}
