// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Property-based tests (proptest) for domain invariants.
//!
//! ## Properties tested
//!
//! 1. **`LexicalSortKey::midpoint`** – generated midpoint is strictly between
//!    its bounds; byte-length growth is bounded; invalid bounds are rejected.
//! 2. **UUIDv7 monotonicity** – sequences of `Uuid::now_v7()` are non-decreasing.
//! 3. **`UserId::from_sub` idempotency** – roundtrip identity and no panic.
//! 4. **`BlockMembership` state machine** – event idempotency, state invariants,
//!    and reapply determinism.

use proptest::prelude::*;

use crate::membership::Role;
use crate::membership::aggregate::BlockMembership;
use crate::membership::aggregate::MembershipState;
use crate::membership::events::MembershipEvent;
use crate::shared::{BlockId, LexicalSortKey, UserId};
use kameo_es::{Apply, Metadata};
use uuid::Uuid;

// ── Strategies ──────────────────────────────────────────────────────

/// Generate a valid `LexicalSortKey` (non-empty, bytes in `[b'!', b'~']`,
/// max 64 chars).
fn any_lexical_sort_key() -> impl Strategy<Value = LexicalSortKey> {
    prop::string::string_regex("[!-~]{1,64}")
        .expect("regex is valid")
        .prop_map(|s| LexicalSortKey::new(s).expect("regex guarantees valid key"))
}

/// Generate any `UserId` from an arbitrary string.
fn any_user_id() -> impl Strategy<Value = UserId> {
    ".*".prop_map(UserId::from_sub)
}

/// Generate a random `BlockId`.
fn any_block_id() -> impl Strategy<Value = BlockId> {
    any::<u128>().prop_map(|v| BlockId::from_uuid(Uuid::from_u128(v)))
}

/// Generate a random `Role`.
fn any_role() -> impl Strategy<Value = Role> {
    prop_oneof![
        Just(Role::CostumeDesigner),
        Just(Role::WardrobeSupervisor),
        Just(Role::CostumeAssistant),
    ]
}

/// Generate a random [`MembershipEvent`] with arbitrary payloads.
fn any_event() -> impl Strategy<Value = MembershipEvent> {
    prop_oneof![
        (any_block_id(), any_user_id(), any_role()).prop_map(|(block_id, user_id, role)| {
            MembershipEvent::MemberInvited {
                block_id,
                user_id,
                role,
            }
        },),
        (any_block_id(), any_user_id(), any_role()).prop_map(|(block_id, user_id, role)| {
            MembershipEvent::InvitationAccepted {
                block_id,
                user_id,
                role,
            }
        },),
        (any_block_id(), any_user_id(), any_role()).prop_map(|(block_id, user_id, role)| {
            MembershipEvent::RoleGranted {
                block_id,
                user_id,
                role,
            }
        },),
        (any_block_id(), any_user_id())
            .prop_map(|(block_id, user_id)| MembershipEvent::MemberRemoved { block_id, user_id },),
        (any_block_id(), any_user_id(), any_role()).prop_map(|(block_id, user_id, role)| {
            MembershipEvent::OwnerBootstrapped {
                block_id,
                user_id,
                role,
            }
        },),
    ]
}

/// Generate a sequence of up to 50 [`MembershipEvent`]s.
fn any_event_sequence() -> impl Strategy<Value = Vec<MembershipEvent>> {
    prop::collection::vec(any_event(), 0..=50)
}

// ── Property 1: LexicalSortKey::midpoint ───────────────────────────

proptest! {
    #[test]
    fn midpoint_strictly_between(
        a in any_lexical_sort_key(),
        b in any_lexical_sort_key(),
    ) {
        prop_assume!(a < b);
        if let Ok(m) = LexicalSortKey::midpoint(&a, &b) {
            prop_assert!(a < m, "midpoint({:?}, {:?}) = {:?} is not > a", a, b, m);
            prop_assert!(m < b, "midpoint({:?}, {:?}) = {:?} is not < b", a, b, m);
        }
        // Err is acceptable for degenerate bounds (key at max length, etc.)
    }

    #[test]
    fn midpoint_growth_bounded(
        a in any_lexical_sort_key(),
        b in any_lexical_sort_key(),
    ) {
        prop_assume!(a < b);
        if let Ok(m) = LexicalSortKey::midpoint(&a, &b) {
            let max_len = a.0.len() + b.0.len() + 1;
            prop_assert!(
                m.0.len() <= max_len,
                "midpoint({:?}, {:?}) len {} exceeds max_len {}",
                a, b, m.0.len(), max_len,
            );
        }
    }

    #[test]
    fn midpoint_rejects_invalid_bounds(
        a in any_lexical_sort_key(),
        b in any_lexical_sort_key(),
    ) {
        prop_assume!(a >= b);
        let result = LexicalSortKey::midpoint(&a, &b);
        prop_assert!(
            result.is_err(),
            "expected NoRoom for a={:?} >= b={:?} but got Ok({:?})",
            a, b, result,
        );
    }

    #[test]
    fn midpoint_produces_valid_key(
        a in any_lexical_sort_key(),
        b in any_lexical_sort_key(),
    ) {
        prop_assume!(a < b);
        if let Ok(m) = LexicalSortKey::midpoint(&a, &b) {
            let roundtrip = LexicalSortKey::new(m.0.clone());
            prop_assert!(
                roundtrip.is_ok(),
                "midpoint({:?}, {:?}) = {:?} is not a valid key: {:?}",
                a, b, m, roundtrip,
            );
            prop_assert_eq!(&roundtrip.unwrap(), &m);
        }
    }
}

// ── Property 2: UUIDv7 monotonicity ────────────────────────────────

// A sequence of Uuid::now_v7() calls produces monotonically non-decreasing
// values (UUIDv7 encodes a millisecond-precision timestamp, so rapid calls
// may share the same timestamp). This guards the event-stream ordering
// assumption used by projectors.
proptest! {
    #[test]
    fn uuid_v7_monotonicity(count in 1usize..100usize) {
        let mut prev = Uuid::now_v7();
        for _ in 0..count {
            let next = Uuid::now_v7();
            prop_assert!(
                prev <= next,
                "UUIDv7 sequence decreased: {:?} > {:?}",
                prev, next,
            );
            prev = next;
        }
    }
}

// ── Property 3: UserId::from_sub idempotency ───────────────────────

// UserId::from_sub(x).as_str() == x for any string – the UserId preserves
// the exact OIDC sub claim it was constructed from. Also verifies it
// never panics regardless of input.
proptest! {
    #[test]
    fn user_id_from_sub_roundtrip(sub in ".*") {
        let id = UserId::from_sub(sub.clone());
        prop_assert_eq!(
            id.as_str(),
            &sub,
            "UserId::from_sub({:?}).as_str() = {:?}",
            sub,
            id.as_str(),
        );
    }

    #[test]
    fn user_id_from_sub_never_panics(sub in "\\PC*") {
        let _id = UserId::from_sub(sub);
    }
}

// ── Helpers for BlockMembership property tests ─────────────────────

/// Create a deterministic initial aggregate for testing.
/// Uses a fixed `BlockId` so that `apply_events` produces idempotent
/// results even for empty event sequences.
fn initial_state() -> BlockMembership {
    BlockMembership {
        block_id: BlockId::from_uuid(uuid::Uuid::from_u128(0)),
        members: std::collections::HashMap::new(),
    }
}

/// Apply a slice of events onto a fresh aggregate, returning the
/// resulting state.
fn apply_events(events: &[MembershipEvent]) -> BlockMembership {
    let mut agg = initial_state();
    for event in events {
        agg.apply(event.clone(), Metadata::default());
    }
    agg
}

/// Check that every user in `Active` state has received at least one
/// `InvitationAccepted` or `OwnerBootstrapped` event in the history.
///
/// A user who was only `MemberInvited` (Pending) should never appear as
/// Active. Note that `RoleGranted` keeps them Active but is *not* a valid
/// activation event — the user must have been activated by either
/// `InvitationAccepted` or `OwnerBootstrapped` first.
fn invariant_active_members_have_activation_event(
    events: &[MembershipEvent],
    state: &BlockMembership,
) -> bool {
    for (user_id, member_state) in &state.members {
        if matches!(member_state, MembershipState::Active { .. }) {
            let was_activated = events.iter().any(|e| match e {
                MembershipEvent::InvitationAccepted { user_id: u, .. }
                | MembershipEvent::OwnerBootstrapped { user_id: u, .. } => u == user_id,
                _ => false,
            });
            if !was_activated {
                return false;
            }
        }
    }
    true
}

// ── Property 4: BlockMembership state machine ──────────────────────

// Idempotency: replaying the same event sequence on two fresh aggregates
// produces identical final states.
proptest! {
    #[test]
    fn membership_idempotent(events in any_event_sequence()) {
        let state1 = apply_events(&events);
        let state2 = apply_events(&events);
        prop_assert_eq!(
            state1, state2,
            "replaying the same events should produce identical state",
        );
    }
}

// State invariant: no user is in Active state without having received an
// InvitationAccepted or OwnerBootstrapped event.
proptest! {
    #[test]
    fn membership_active_must_have_acceptance_event(events in any_event_sequence()) {
        let state = apply_events(&events);
        prop_assert!(
            invariant_active_members_have_activation_event(&events, &state),
            "Active member without corresponding Accepted or Bootstrapped event",
        );
    }
}

// Reapply idempotency: applying the same event sequence twice on the same
// aggregate does not change state after the first pass.
proptest! {
    #[test]
    fn membership_reapply_does_not_change_state(events in any_event_sequence()) {
        let mut state = BlockMembership::default();
        for event in &events {
            state.apply(event.clone(), Metadata::default());
        }
        let state_after_first = state.clone();

        // Re-apply every event once more
        for event in &events {
            state.apply(event.clone(), Metadata::default());
        }
        prop_assert_eq!(
            state, state_after_first,
            "re-applying events should not change state",
        );
    }
}
