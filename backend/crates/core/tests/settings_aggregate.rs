// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use breakdown_core::settings::{
    CreateCredentialBinding, CredentialBindingState, RevokeCredential, SettingsAggregate,
    SettingsEvent,
};
use breakdown_core::shared::AggregateVersion;
use kameo_es::{Apply, Command, Metadata};
use serde_json::to_string;
use test_support::make_ctx;
use uuid::Uuid;

fn binding() -> CreateCredentialBinding {
    CreateCredentialBinding {
        id: Uuid::now_v7(),
        provider: "gdrive".into(),
        vault_key_id: "settings-01900000-0000-7000-8000-000000000001".into(),
        vault_version: 1,
    }
}

#[test]
fn events_are_reference_only() {
    let command = binding();
    let events = SettingsAggregate::default()
        .handle(command, make_ctx())
        .unwrap();
    let encoded = to_string(&events).unwrap();
    assert!(encoded.contains("vault_key_id"));
    assert!(!encoded.contains("secret"));
    assert!(!encoded.contains("refresh_token"));
}

#[test]
fn binding_apply_and_revoke_are_reference_only() {
    let command = binding();
    let id = command.id;
    let mut aggregate = SettingsAggregate::default();
    let events = aggregate.handle(command, make_ctx()).unwrap();
    aggregate.apply(events.into_iter().next().unwrap(), Metadata::default());
    assert_eq!(aggregate.id, id);
    assert_eq!(
        aggregate.binding_state,
        Some(CredentialBindingState::Active)
    );
    assert_eq!(aggregate.version, AggregateVersion::INITIAL);

    let revoke = aggregate
        .handle(
            RevokeCredential {
                id,
                version: AggregateVersion::INITIAL,
            },
            make_ctx(),
        )
        .unwrap();
    aggregate.apply(revoke.into_iter().next().unwrap(), Metadata::default());
    assert_eq!(
        aggregate.binding_state,
        Some(CredentialBindingState::Revoked)
    );
    assert_eq!(aggregate.version, AggregateVersion(2));
}

#[test]
fn invalid_binding_is_rejected() {
    let command = CreateCredentialBinding {
        id: Uuid::now_v7(),
        provider: " ".into(),
        vault_key_id: "key".into(),
        vault_version: 1,
    };
    assert!(
        SettingsAggregate::default()
            .handle(command, make_ctx())
            .is_err()
    );
}

#[test]
fn event_type_names_are_stable() {
    let event = SettingsEvent::CredentialBound {
        id: Uuid::now_v7(),
        provider: "ai".into(),
        vault_key_id: "settings-key".into(),
        vault_version: 1,
        version: AggregateVersion::INITIAL,
    };
    assert_eq!(kameo_es::EventType::event_type(&event), "CredentialBound");
}
