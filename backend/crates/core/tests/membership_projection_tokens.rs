// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy4-preview (opencode-go)

//! `Role` / `MembershipStateKind` carry **two** stable textual
//! representations, and they must agree on the same `snake_case` token:
//!
//! * the **wire** form — serde JSON (`"costume_assistant"`, `"active"`), which
//!   is what `MembershipView` serializes to and what the API contract
//!   (`backend/openapi.yaml`) promises to clients;
//! * the **storage** form — the plain token (`costume_assistant`, `active`)
//!   written into `projection_membership.role` / `.state` by the membership
//!   projector, because the membership authorization predicates compare those
//!   columns against plain SQL string literals (`m.state = 'active'`,
//!   `m.role IN ('costume_designer', …)`).
//!
//! The mismatch these tests guard against is silent and security-relevant: if
//! the two forms drift apart, the predicates stop matching any row and every
//! gate built on them fails closed (issue #342).

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use breakdown_core::membership::Role;
use breakdown_core::membership::views::MembershipStateKind;

/// The plain token must be the JSON form without its quotes.
#[test]
fn role_token_matches_the_serde_wire_form() {
    for role in [
        Role::CostumeDesigner,
        Role::WardrobeSupervisor,
        Role::CostumeAssistant,
    ] {
        let wire = serde_json::to_string(&role).expect("Role serializes to JSON");
        assert_eq!(
            wire,
            format!("\"{}\"", role.as_str()),
            "storage token and wire form must agree for {role:?}"
        );
    }
}

/// …and the same for the membership lifecycle state.
#[test]
fn state_token_matches_the_serde_wire_form() {
    for state in [MembershipStateKind::Pending, MembershipStateKind::Active] {
        let wire = serde_json::to_string(&state).expect("state serializes to JSON");
        assert_eq!(
            wire,
            format!("\"{}\"", state.as_str()),
            "storage token and wire form must agree for {state:?}"
        );
    }
}

/// The tokens the authz SQL compares against are literals in
/// `crates/infra/src/queries/membership.rs`; pin them here so renaming a token
/// cannot silently break those predicates.
#[test]
fn storage_tokens_are_the_expected_snake_case_literals() {
    assert_eq!(Role::CostumeDesigner.as_str(), "costume_designer");
    assert_eq!(Role::WardrobeSupervisor.as_str(), "wardrobe_supervisor");
    assert_eq!(Role::CostumeAssistant.as_str(), "costume_assistant");
    assert_eq!(MembershipStateKind::Pending.as_str(), "pending");
    assert_eq!(MembershipStateKind::Active.as_str(), "active");
}

/// Round-trip: every token parses back to its variant, unknown input is
/// rejected instead of defaulting (a default would be an authorization bug).
#[test]
fn tokens_round_trip_and_unknown_input_is_rejected() {
    for role in [
        Role::CostumeDesigner,
        Role::WardrobeSupervisor,
        Role::CostumeAssistant,
    ] {
        assert_eq!(Role::from_token(role.as_str()), Some(role));
    }
    for state in [MembershipStateKind::Pending, MembershipStateKind::Active] {
        assert_eq!(MembershipStateKind::from_token(state.as_str()), Some(state));
    }

    // The JSON form must NOT parse as a token: that representation belongs on
    // the wire, and accepting it would mask a stale projection row.
    assert_eq!(Role::from_token("\"costume_designer\""), None);
    assert_eq!(MembershipStateKind::from_token("\"active\""), None);
    assert_eq!(Role::from_token(""), None);
    assert_eq!(MembershipStateKind::from_token("Administrator"), None);
}
