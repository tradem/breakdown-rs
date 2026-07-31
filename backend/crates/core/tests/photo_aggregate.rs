// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::photo::*;
use breakdown_core::shared::{AggregateVersion, PhotoId, PhotoVariant, VariantStatus};
use kameo_es::{Apply, Command};
use test_support::make_ctx;

fn make_uploaded_photo() -> PhotoAggregate {
    let agg = PhotoAggregate::default();
    let events = agg
        .handle(
            UploadPhoto {
                id: PhotoId::new(),
                content_type: "image/jpeg".into(),
                size_bytes: 1024 * 1024,
                binding: PhotoBinding::default(),
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = PhotoAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_upload_emits_photo_uploaded_with_pending_variants() {
    let id = PhotoId::new();
    let result = PhotoAggregate::default().handle(
        UploadPhoto {
            id,
            content_type: "image/jpeg".into(),
            size_bytes: 5000,
            binding: PhotoBinding::default(),
        },
        make_ctx(),
    );
    assert!(result.is_ok());
    match result.unwrap().into_iter().next().unwrap() {
        PhotoEvent::PhotoUploaded {
            id: eid,
            content_type,
            size_bytes,
            variant_statuses,
            binding,
            version,
        } => {
            assert_eq!(eid, id);
            assert_eq!(content_type, "image/jpeg");
            assert_eq!(size_bytes, 5000);
            assert_eq!(binding, PhotoBinding::default());
            assert_eq!(version, AggregateVersion::INITIAL);
            assert_eq!(variant_statuses.len(), 3);
            assert!(variant_statuses.contains(&(PhotoVariant::Original, VariantStatus::Pending)));
            assert!(variant_statuses.contains(&(PhotoVariant::Thumb, VariantStatus::Pending)));
            assert!(variant_statuses.contains(&(PhotoVariant::Medium, VariantStatus::Pending)));
        }
        _ => panic!("Expected PhotoUploaded"),
    }
}

#[test]
fn test_normalize_original_success() {
    let mut agg = make_uploaded_photo();
    let events = agg
        .handle(
            NormalizeOriginal {
                id: agg.id,
                new_size: 900000,
                rotated: true,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    assert_eq!(agg.size_bytes, 900000);
    assert!(agg.exif_stripped_at.is_some());
    assert_eq!(
        agg.variants
            .iter()
            .find(|v| v.kind == PhotoVariant::Original)
            .map(|v| v.status),
        Some(VariantStatus::Ready)
    );
}

#[test]
fn test_generate_variant_success() {
    let mut agg = make_uploaded_photo();
    let version = agg.version;

    let events = agg
        .handle(
            GenerateVariant {
                id: agg.id,
                variant: PhotoVariant::Thumb,
                size_bytes: 50000,
                version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    assert_eq!(
        agg.variants
            .iter()
            .find(|v| v.kind == PhotoVariant::Thumb)
            .map(|v| v.status),
        Some(VariantStatus::Ready)
    );
}

#[test]
fn test_generate_variant_wrong_version() {
    let agg = make_uploaded_photo();
    let result = agg.handle(
        GenerateVariant {
            id: agg.id,
            variant: PhotoVariant::Thumb,
            size_bytes: 50000,
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
}

#[test]
fn test_mark_variant_failed() {
    let mut agg = make_uploaded_photo();
    let events = agg
        .handle(
            MarkVariantFailed {
                id: agg.id,
                variant: PhotoVariant::Thumb,
                error: "OOM".into(),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    assert_eq!(
        agg.variants
            .iter()
            .find(|v| v.kind == PhotoVariant::Thumb)
            .map(|v| v.status),
        Some(VariantStatus::Failed)
    );
}

#[test]
fn test_delete_photo_success() {
    let agg = make_uploaded_photo();
    let result = agg.handle(
        DeletePhoto {
            id: agg.id,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_ok());
    let events = result.unwrap();
    assert_eq!(events.len(), 1);
    assert!(matches!(events[0], PhotoEvent::PhotoDeleted { .. }));
}

#[test]
fn test_delete_photo_wrong_version() {
    let agg = make_uploaded_photo();
    let result = agg.handle(
        DeletePhoto {
            id: agg.id,
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
}

#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = PhotoAggregate::default();
    let id = PhotoId::new();
    agg.apply(
        PhotoEvent::PhotoUploaded {
            id,
            content_type: "image/png".into(),
            size_bytes: 2048,
            variant_statuses: vec![],
            binding: PhotoBinding::default(),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(agg.id, id);
    assert_eq!(agg.content_type, "image/png");
    assert_eq!(agg.size_bytes, 2048);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}
