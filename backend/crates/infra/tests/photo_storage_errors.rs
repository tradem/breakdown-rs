// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash-free (opencode)

//! Deterministic classification tests for the photo-storage OpenDAL error
//! boundary (issue #165 ack semantics): temporary storage failures must
//! surface as `ServiceUnavailable` so the saga `retry_transient` loop can
//! retry them in-loop instead of failing the event, while permanent errors
//! map to `ValidationError` and reach the ack-after-success redelivery path.
//!
//! Both `store` (write boundary) and `delete_all` (delete boundary) classify
//! their OpenDAL errors through [`infra::photo::storage::map_storage_error`],
//! so exercising the mapping covers both boundaries deterministically.

use breakdown_core::error::DomainError;
use infra::photo::storage::map_storage_error;

fn temporary_error() -> opendal::Error {
    opendal::Error::new(
        opendal::ErrorKind::Unexpected,
        "garage temporarily unreachable",
    )
    .set_temporary()
}

#[test]
fn temporary_write_failure_is_service_unavailable() {
    // Write boundary (`store`): a temporary OpenDAL error must be retried by
    // `retry_transient`, never treated as a permanent failure.
    let err = map_storage_error("photo/123/original", temporary_error());
    assert!(matches!(err, DomainError::ServiceUnavailable { .. }));
}

#[test]
fn temporary_delete_failure_is_service_unavailable() {
    // Delete boundary (`delete_all`): a temporary OpenDAL error must be
    // retried in-loop so the event is not acknowledged while the object
    // still exists in storage.
    let err = map_storage_error("photo/123/thumb", temporary_error());
    assert!(matches!(err, DomainError::ServiceUnavailable { .. }));
}

#[test]
fn permanent_failure_is_validation_error() {
    // Permanent failures are not retried in-loop; they fail the event and
    // rely on ack-after-success redelivery.
    let err = map_storage_error(
        "photo/123/original",
        opendal::Error::new(opendal::ErrorKind::Unexpected, "checksum mismatch"),
    );
    assert!(matches!(err, DomainError::Validation { .. }));
    assert!(err.to_string().contains("photo/123/original"));
}
