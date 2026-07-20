use super::*;
use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::LazyLock;
use std::time::Instant;

use chrono::Utc;
use kameo_es::{Context, Entity, Metadata, StreamId};

use crate::shared::{BlockId, UserId};

use crate::membership::Role;

type CausationTracking = HashMap<StreamId, (u64, HashSet<Cow<'static, str>>)>;

/// Build a `Context` with the given `actor` in command metadata. Leaks a
/// `Box`ed `Metadata` to obtain a `&'static` reference (test-only,
/// mirroring `test_support::make_ctx` but for `Metadata =
/// MembershipMetadata`).
fn ctx_with(actor: Option<UserId>) -> Context<'static, BlockMembership> {
    static TRACKING: LazyLock<CausationTracking> = LazyLock::new(HashMap::new);
    let metadata: &'static Metadata<MembershipMetadata> = Box::leak(Box::new(Metadata {
        data: Some(MembershipMetadata { actor }),
        ..Default::default()
    }));
    Context {
        metadata,
        causation_tracking: &TRACKING,
        time: Utc::now(),
        executed_at: Instant::now(),
    }
}

/// Replay events onto the aggregate (local variant: membership uses a
/// non-`()` metadata, so `test_support::replay_events` does not apply).
fn replay(agg: &mut BlockMembership, events: impl IntoIterator<Item = MembershipEvent>) {
    for e in events {
        agg.apply(e, Metadata::default());
    }
}

/// Dispatch a command and apply its emitted events to `agg` in one step.
///
/// Takes a closure so the immutable borrow during `handle` ends before the
/// mutable borrow in `replay` — this avoids a borrow conflict in the caller
/// that would occur with `replay(&mut agg, agg.handle(..).unwrap())`.
fn run(
    agg: &mut BlockMembership,
    f: impl FnOnce(&BlockMembership) -> Result<Vec<MembershipEvent>, MembershipError>,
) {
    let events = f(agg).expect("command should succeed");
    replay(agg, events);
}

fn block_id() -> BlockId {
    BlockId::new()
}

fn user(sub: &str) -> UserId {
    UserId::from_sub(sub.to_string())
}

#[test]
fn invite_emits_member_invited_and_is_pending() {
    let agg = BlockMembership::default();
    let cmd = InviteMember {
        block_id: block_id(),
        user_id: user("alice"),
        role: Role::CostumeDesigner,
    };
    let events = agg.handle(cmd, ctx_with(None)).unwrap();
    assert_eq!(events.len(), 1);
    assert!(matches!(
        events[0],
        MembershipEvent::MemberInvited {
            role: Role::CostumeDesigner,
            ..
        }
    ));
}

#[test]
fn re_invite_existing_user_is_rejected() {
    let mut agg = BlockMembership::default();
    let cmd = InviteMember {
        block_id: block_id(),
        user_id: user("alice"),
        role: Role::CostumeDesigner,
    };
    run(&mut agg, |a| a.handle(cmd.clone(), ctx_with(None)));

    let result = agg.handle(cmd, ctx_with(None));
    assert!(matches!(
        result,
        Err(MembershipError::AlreadyInvited { .. })
    ));
}

#[test]
fn accept_pending_invitation_becomes_active() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let alice = user("alice");
    run(&mut agg, |a| {
        a.handle(
            InviteMember {
                block_id: b,
                user_id: alice.clone(),
                role: Role::CostumeDesigner,
            },
            ctx_with(None),
        )
    });

    let events = agg
        .handle(
            AcceptInvitation {
                block_id: b,
                user_id: alice.clone(),
            },
            ctx_with(None),
        )
        .unwrap();
    assert!(matches!(
        events[0],
        MembershipEvent::InvitationAccepted {
            role: Role::CostumeDesigner,
            ..
        }
    ));
    replay(&mut agg, events);
    assert!(matches!(
        agg.members.get(&alice),
        Some(MembershipState::Active {
            role: Role::CostumeDesigner
        })
    ));
}

#[test]
fn accept_without_pending_is_rejected() {
    let agg = BlockMembership::default();
    let result = agg.handle(
        AcceptInvitation {
            block_id: block_id(),
            user_id: user("bob"),
        },
        ctx_with(None),
    );
    assert!(matches!(
        result,
        Err(MembershipError::NoPendingInvitation { .. })
    ));
}

#[test]
fn grant_role_to_active_member_replaces_role() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let bob = user("bob");
    run(&mut agg, |a| {
        a.handle(
            InviteMember {
                block_id: b,
                user_id: bob.clone(),
                role: Role::CostumeDesigner,
            },
            ctx_with(None),
        )
    });
    run(&mut agg, |a| {
        a.handle(
            AcceptInvitation {
                block_id: b,
                user_id: bob.clone(),
            },
            ctx_with(None),
        )
    });

    let events = agg
        .handle(
            GrantRole {
                block_id: b,
                user_id: bob.clone(),
                role: Role::WardrobeSupervisor,
            },
            ctx_with(None),
        )
        .unwrap();
    assert!(matches!(
        events[0],
        MembershipEvent::RoleGranted {
            role: Role::WardrobeSupervisor,
            ..
        }
    ));
    replay(&mut agg, events);
    assert!(matches!(
        agg.members.get(&bob),
        Some(MembershipState::Active {
            role: Role::WardrobeSupervisor
        })
    ));
}

#[test]
fn grant_role_to_non_member_is_rejected() {
    let agg = BlockMembership::default();
    let result = agg.handle(
        GrantRole {
            block_id: block_id(),
            user_id: user("carol"),
            role: Role::WardrobeSupervisor,
        },
        ctx_with(None),
    );
    assert!(matches!(
        result,
        Err(MembershipError::NotActiveMember { .. })
    ));
}

#[test]
fn remove_active_member_emits_member_removed() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let dave = user("dave");
    run(&mut agg, |a| {
        a.handle(
            InviteMember {
                block_id: b,
                user_id: dave.clone(),
                role: Role::WardrobeSupervisor,
            },
            ctx_with(None),
        )
    });
    run(&mut agg, |a| {
        a.handle(
            AcceptInvitation {
                block_id: b,
                user_id: dave.clone(),
            },
            ctx_with(None),
        )
    });

    let events = agg
        .handle(
            RemoveMember {
                block_id: b,
                user_id: dave.clone(),
            },
            ctx_with(None),
        )
        .unwrap();
    assert!(matches!(events[0], MembershipEvent::MemberRemoved { .. }));
    replay(&mut agg, events);
    assert!(!agg.members.contains_key(&dave));
}

#[test]
fn remove_non_member_is_rejected() {
    let agg = BlockMembership::default();
    let result = agg.handle(
        RemoveMember {
            block_id: block_id(),
            user_id: user("eve"),
        },
        ctx_with(None),
    );
    assert!(matches!(
        result,
        Err(MembershipError::NotActiveMember { .. })
    ));
}

#[test]
fn leave_block_as_active_member_removes_self() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let frank = user("frank");
    run(&mut agg, |a| {
        a.handle(
            InviteMember {
                block_id: b,
                user_id: frank.clone(),
                role: Role::CostumeDesigner,
            },
            ctx_with(None),
        )
    });
    run(&mut agg, |a| {
        a.handle(
            AcceptInvitation {
                block_id: b,
                user_id: frank.clone(),
            },
            ctx_with(None),
        )
    });

    let events = agg
        .handle(LeaveBlock { block_id: b }, ctx_with(Some(frank.clone())))
        .unwrap();
    assert!(matches!(
        events[0],
        MembershipEvent::MemberRemoved { ref user_id, .. }
            if *user_id == frank
    ));
    replay(&mut agg, events);
    assert!(!agg.members.contains_key(&frank));
}

#[test]
fn leave_block_without_actor_is_rejected() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let grace = user("grace");
    run(&mut agg, |a| {
        a.handle(
            InviteMember {
                block_id: b,
                user_id: grace.clone(),
                role: Role::CostumeDesigner,
            },
            ctx_with(None),
        )
    });
    run(&mut agg, |a| {
        a.handle(
            AcceptInvitation {
                block_id: b,
                user_id: grace.clone(),
            },
            ctx_with(None),
        )
    });

    let result = agg.handle(LeaveBlock { block_id: b }, ctx_with(None));
    assert!(matches!(result, Err(MembershipError::MissingActor)));
}

#[test]
fn leave_block_as_non_member_is_rejected() {
    let agg = BlockMembership::default();
    let result = agg.handle(
        LeaveBlock {
            block_id: block_id(),
        },
        ctx_with(Some(user("heidi"))),
    );
    assert!(matches!(
        result,
        Err(MembershipError::NotActiveMember { .. })
    ));
}

#[test]
fn bootstrap_owner_seeds_first_active_member() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let owner = user("owner");
    let events = agg
        .handle(
            BootstrapOwner {
                block_id: b,
                user_id: owner.clone(),
                role: Role::CostumeAssistant,
            },
            ctx_with(Some(owner.clone())),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    assert!(matches!(
        events[0],
        MembershipEvent::OwnerBootstrapped {
            role: Role::CostumeAssistant,
            ..
        }
    ));
    replay(&mut agg, events);
    assert!(matches!(
        agg.members.get(&owner),
        Some(MembershipState::Active {
            role: Role::CostumeAssistant
        })
    ));
}

#[test]
fn bootstrap_owner_rejected_when_block_already_has_members() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    // Seed one normal (invited + accepted) member first.
    run(&mut agg, |a| {
        a.handle(
            InviteMember {
                block_id: b,
                user_id: user("alice"),
                role: Role::CostumeDesigner,
            },
            ctx_with(None),
        )
    });
    run(&mut agg, |a| {
        a.handle(
            AcceptInvitation {
                block_id: b,
                user_id: user("alice"),
            },
            ctx_with(None),
        )
    });

    let result = agg.handle(
        BootstrapOwner {
            block_id: b,
            user_id: user("owner"),
            role: Role::CostumeAssistant,
        },
        ctx_with(Some(user("owner"))),
    );
    assert!(matches!(
        result,
        Err(MembershipError::BootstrapNotAllowed { .. })
    ));
}

#[test]
fn bootstrap_owner_is_idempotent_under_redelivery() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let owner = user("owner");
    let evt = MembershipEvent::OwnerBootstrapped {
        block_id: b,
        user_id: owner.clone(),
        role: Role::CostumeAssistant,
    };
    agg.apply(evt.clone(), Metadata::default());
    agg.apply(evt, Metadata::default()); // deliver twice
    assert!(matches!(
        agg.members.get(&owner),
        Some(MembershipState::Active {
            role: Role::CostumeAssistant
        })
    ));
}

/// Verify `apply` is idempotent under redelivery: re-applying the same
/// accepted-invitation event yields identical state (catches mutants that
/// append instead of insert).
#[test]
fn apply_is_idempotent_under_redelivery() {
    let mut agg = BlockMembership::default();
    let b = block_id();
    let ivan = user("ivan");
    let evt = MembershipEvent::InvitationAccepted {
        block_id: b,
        user_id: ivan.clone(),
        role: Role::WardrobeSupervisor,
    };
    agg.apply(evt.clone(), Metadata::default());
    agg.apply(evt, Metadata::default()); // deliver twice
    assert!(matches!(
        agg.members.get(&ivan),
        Some(MembershipState::Active {
            role: Role::WardrobeSupervisor
        })
    ));
}

/// Verify the `Entity` category + id type contract (catches mutants that
/// rename the category or change the id type).
#[test]
fn entity_contract() {
    assert_eq!(BlockMembership::category(), "membership");
    let _: Uuid = Uuid::now_v7();
}
