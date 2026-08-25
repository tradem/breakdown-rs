// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use breakdown_core::settings::{
    CreateCredentialBinding, CredentialBindingState, GDriveCredentialBundle, RevokeCredential,
    RotateCredentialBinding, SettingsAggregate, SettingsError, SettingsEvent,
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
fn gdrive_bundle_round_trips_through_vault_encoding() {
    let bundle = GDriveCredentialBundle::try_new(
        " client-id\n".into(),
        "client-secret\t".into(),
        "refresh-token ".into(),
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
fn gdrive_bundle_rejects_blank_required_fields() {
    assert!(
        GDriveCredentialBundle::try_new(
            "  ".into(),
            "client-secret".into(),
            "refresh-token".into(),
            None,
        )
        .is_err()
    );
    assert!(
        GDriveCredentialBundle::try_new(
            "client-id".into(),
            "client-secret".into(),
            "\t\n".into(),
            None,
        )
        .is_err()
    );
}

#[test]
fn gdrive_bundle_normalizes_blank_root_folder_to_none() {
    let bundle = GDriveCredentialBundle::try_new(
        "client-id".into(),
        "client-secret".into(),
        "refresh-token".into(),
        Some("   ".into()),
    )
    .unwrap();
    assert_eq!(bundle.root_folder_id(), None);
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
    let encoded = serde_json::to_value(&rotated[0]).unwrap();
    let payload = encoded
        .get("CredentialRotated")
        .unwrap()
        .as_object()
        .unwrap();
    let mut fields: Vec<&str> = payload.keys().map(String::as_str).collect();
    fields.sort_unstable();
    assert_eq!(
        fields,
        vec!["id", "provider", "vault_key_id", "vault_version", "version"]
    );
    assert_eq!(payload["vault_key_id"], "settings-new-key");
    aggregate.apply(rotated.into_iter().next().unwrap(), Metadata::default());
    assert_eq!(aggregate.vault_key_id, "settings-new-key");
    assert_eq!(aggregate.version, AggregateVersion(2));
}

#[test]
fn rotate_rejects_missing_revoked_and_invalid_bindings() {
    let command = RotateCredentialBinding {
        id: Uuid::now_v7(),
        provider: "gdrive".into(),
        vault_key_id: "settings-new-key".into(),
        vault_version: 2,
        version: AggregateVersion::INITIAL,
    };
    assert!(matches!(
        SettingsAggregate::default().handle(command.clone(), make_ctx()),
        Err(SettingsError::NotFound)
    ));

    let initial = binding();
    let id = initial.id;
    let mut revoked = SettingsAggregate::default();
    let created = revoked.handle(initial, make_ctx()).unwrap();
    revoked.apply(created.into_iter().next().unwrap(), Metadata::default());
    let event = revoked
        .handle(
            RevokeCredential {
                id,
                version: AggregateVersion::INITIAL,
            },
            make_ctx(),
        )
        .unwrap();
    revoked.apply(event.into_iter().next().unwrap(), Metadata::default());
    assert!(matches!(
        revoked.handle(command.clone(), make_ctx()),
        Err(SettingsError::AlreadyRevoked)
    ));

    let mut active = SettingsAggregate::default();
    let created = active.handle(binding(), make_ctx()).unwrap();
    active.apply(created.into_iter().next().unwrap(), Metadata::default());
    assert!(matches!(
        active.handle(
            RotateCredentialBinding {
                provider: "other".into(),
                ..command.clone()
            },
            make_ctx(),
        ),
        Err(SettingsError::ProviderMismatch)
    ));
    assert!(matches!(
        active.handle(
            RotateCredentialBinding {
                provider: "".into(),
                ..command.clone()
            },
            make_ctx(),
        ),
        Err(SettingsError::EmptyProvider)
    ));
    assert!(matches!(
        active.handle(
            RotateCredentialBinding {
                vault_key_id: "".into(),
                ..command.clone()
            },
            make_ctx(),
        ),
        Err(SettingsError::EmptyVaultKey)
    ));
    assert!(matches!(
        active.handle(
            RotateCredentialBinding {
                version: AggregateVersion(99),
                ..command
            },
            make_ctx(),
        ),
        Err(SettingsError::VersionMismatch { .. })
    ));
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

// ---------------------------------------------------------------------------
// P1.4 — Key-Material: Debug redaction, has_same_material, Zeroize/Drop
// ---------------------------------------------------------------------------

/// `SecretValue::Debug` must never leak the plaintext secret.
#[test]
fn secret_value_debug_redacts_plaintext() {
    let secret = breakdown_core::settings::ports::SecretValue::new("super-secret".into());
    let debug = format!("{:?}", secret);
    assert!(
        !debug.contains("super-secret"),
        "Debug must not leak secret"
    );
    assert!(
        debug.contains("<redacted>"),
        "Debug should show redacted marker"
    );
}

/// `has_same_material` returns `true` only when all four fields match.
#[test]
fn has_same_material_identical_bundles() {
    let a = GDriveCredentialBundle::try_new(
        "cid".into(),
        "csecret".into(),
        "rtoken".into(),
        Some("folder1".into()),
    )
    .unwrap();
    let b = GDriveCredentialBundle::try_new(
        "cid".into(),
        "csecret".into(),
        "rtoken".into(),
        Some("folder1".into()),
    )
    .unwrap();
    assert!(a.has_same_material(&b));
}

/// `has_same_material` returns `false` when `client_id` differs.
#[test]
fn has_same_material_differs_on_client_id() {
    let a = GDriveCredentialBundle::try_new("cid-a".into(), "secret".into(), "token".into(), None)
        .unwrap();
    let b = GDriveCredentialBundle::try_new("cid-b".into(), "secret".into(), "token".into(), None)
        .unwrap();
    assert!(!a.has_same_material(&b));
}

/// `has_same_material` returns `false` when `client_secret` differs.
#[test]
fn has_same_material_differs_on_client_secret() {
    let a = GDriveCredentialBundle::try_new("cid".into(), "secret-a".into(), "token".into(), None)
        .unwrap();
    let b = GDriveCredentialBundle::try_new("cid".into(), "secret-b".into(), "token".into(), None)
        .unwrap();
    assert!(!a.has_same_material(&b));
}

/// `has_same_material` returns `false` when `refresh_token` differs.
#[test]
fn has_same_material_differs_on_refresh_token() {
    let a = GDriveCredentialBundle::try_new("cid".into(), "secret".into(), "token-a".into(), None)
        .unwrap();
    let b = GDriveCredentialBundle::try_new("cid".into(), "secret".into(), "token-b".into(), None)
        .unwrap();
    assert!(!a.has_same_material(&b));
}

/// `has_same_material` returns `false` when `root_folder_id` differs.
#[test]
fn has_same_material_differs_on_root_folder_id() {
    let a = GDriveCredentialBundle::try_new(
        "cid".into(),
        "secret".into(),
        "token".into(),
        Some("folder-a".into()),
    )
    .unwrap();
    let b = GDriveCredentialBundle::try_new(
        "cid".into(),
        "secret".into(),
        "token".into(),
        Some("folder-b".into()),
    )
    .unwrap();
    assert!(!a.has_same_material(&b));
}

/// `has_same_material` returns `false` when one bundle has `root_folder_id`
/// and the other does not.
#[test]
fn has_same_material_differs_on_root_folder_presence() {
    let a = GDriveCredentialBundle::try_new(
        "cid".into(),
        "secret".into(),
        "token".into(),
        Some("folder".into()),
    )
    .unwrap();
    let b = GDriveCredentialBundle::try_new("cid".into(), "secret".into(), "token".into(), None)
        .unwrap();
    assert!(!a.has_same_material(&b));
}
