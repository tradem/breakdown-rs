// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use breakdown_core::settings::{
    CreateCredentialBinding, CredentialBindingState, GDriveCredentialBundle, RevokeCredential,
    RotateCredentialBinding, SettingsAggregate, SettingsEvent,
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
fn gdrive_bundle_roundtrips_without_exposing_material_in_events() {
    let bundle = GDriveCredentialBundle::try_new(
        "client-id".into(),
        "client-secret".into(),
        "refresh-token".into(),
        Some("root-folder".into()),
    )
    .unwrap();
    let encoded = bundle.into_secret_value().unwrap();
    assert!(encoded.as_str().contains("client-id"));
    assert!(encoded.as_str().contains("refresh-token"));
    let decoded = GDriveCredentialBundle::from_secret_value(encoded).unwrap();
    assert_eq!(decoded.client_id(), "client-id");
    assert_eq!(decoded.client_secret(), "client-secret");
    assert_eq!(decoded.refresh_token(), "refresh-token");
    assert_eq!(decoded.root_folder_id(), Some("root-folder"));
}

#[test]
fn rotate_event_replaces_reference_and_keeps_secret_free_payload() {
    let command = binding();
    let id = command.id;
    let mut aggregate = SettingsAggregate::default();
    let events = aggregate.handle(command, make_ctx()).unwrap();
    aggregate.apply(events.into_iter().next().unwrap(), Metadata::default());
    let rotated = aggregate
        .handle(
            RotateCredentialBinding {
                id,
                provider: "gdrive".into(),
                vault_key_id: "settings-new-key".into(),
                vault_version: 2,
                version: AggregateVersion::INITIAL,
            },
            make_ctx(),
        )
        .unwrap();
    let encoded = to_string(&rotated).unwrap();
    assert!(encoded.contains("settings-new-key"));
    assert!(!encoded.contains("refresh_token"));
    aggregate.apply(rotated.into_iter().next().unwrap(), Metadata::default());
    assert_eq!(aggregate.vault_key_id, "settings-new-key");
    assert_eq!(aggregate.version, AggregateVersion(2));
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
