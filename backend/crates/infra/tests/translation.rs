// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use breakdown_core::shared::AggregateVersion;
use infra::event_store::{
    check_nonzero_version, domain_to_stream, stream_to_domain, version_from_current,
};

#[test]
fn stream_to_domain_basic() {
    assert_eq!(stream_to_domain(0), AggregateVersion(1));
    assert_eq!(stream_to_domain(1), AggregateVersion(2));
    assert_eq!(stream_to_domain(99), AggregateVersion(100));
}

#[test]
fn domain_to_stream_basic() {
    assert_eq!(domain_to_stream(AggregateVersion(1)), Some(0));
    assert_eq!(domain_to_stream(AggregateVersion(2)), Some(1));
    assert_eq!(domain_to_stream(AggregateVersion(100)), Some(99));
}

#[test]
fn domain_to_stream_zero_returns_none() {
    assert_eq!(domain_to_stream(AggregateVersion(0)), None);
}

#[test]
fn version_from_current_current() {
    assert_eq!(
        version_from_current(sierradb_client::CurrentVersion::Current(0)),
        AggregateVersion(1)
    );
    assert_eq!(
        version_from_current(sierradb_client::CurrentVersion::Current(5)),
        AggregateVersion(6)
    );
}

#[test]
fn version_from_current_empty() {
    assert_eq!(
        version_from_current(sierradb_client::CurrentVersion::Empty),
        AggregateVersion(0)
    );
}

#[test]
fn check_nonzero_version_rejects_zero() {
    let result = check_nonzero_version(AggregateVersion(0));
    assert!(result.is_err());
}

#[test]
fn check_nonzero_version_accepts_initial() {
    let result = check_nonzero_version(AggregateVersion::INITIAL);
    assert!(result.is_ok());
}

#[test]
fn roundtrip_stream_domain() {
    for sv in 0..100 {
        let domain = stream_to_domain(sv);
        assert_eq!(domain_to_stream(domain), Some(sv));
    }
}
