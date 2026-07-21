// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use crate::shared::PhotoVariant;
use test_support::make_ctx;

fn make_uploaded_photo() -> PhotoAggregate {
    let agg = PhotoAggregate::default();
    let events = agg
        .handle(
            UploadPhoto {
                id: PhotoId::new(),
                content_type: "image/jpeg".into(),
                size_bytes: 1024 * 1024,
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
            version,
        } => {
            assert_eq!(eid, id);
            assert_eq!(content_type, "image/jpeg");
            assert_eq!(size_bytes, 5000);
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
                size_bytes: 20000,
                version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    let thumb = agg
        .variants
        .iter()
        .find(|v| v.kind == PhotoVariant::Thumb)
        .unwrap();
    assert_eq!(thumb.status, VariantStatus::Ready);
    assert_eq!(thumb.size_bytes, 20000);
}

#[test]
fn test_generate_variant_already_ready_rejected() {
    let mut agg = make_uploaded_photo();
    let version = agg.version;

    // First generate succeeds
    let events = agg
        .handle(
            GenerateVariant {
                id: agg.id,
                variant: PhotoVariant::Thumb,
                size_bytes: 20000,
                version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    // Second generate for same variant is rejected
    let err = agg
        .handle(
            GenerateVariant {
                id: agg.id,
                variant: PhotoVariant::Thumb,
                size_bytes: 25000,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap_err();
    assert!(matches!(err, PhotoError::ValidationError(_)));
}

#[test]
fn test_mark_variant_failed() {
    let mut agg = make_uploaded_photo();
    let version = agg.version;

    let events = agg
        .handle(
            MarkVariantFailed {
                id: agg.id,
                variant: PhotoVariant::Medium,
                error: "Decode error: unsupported color format".into(),
                version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    let medium = agg
        .variants
        .iter()
        .find(|v| v.kind == PhotoVariant::Medium)
        .unwrap();
    assert_eq!(medium.status, VariantStatus::Failed);
}

#[test]
fn test_delete_photo_is_terminal() {
    let mut agg = make_uploaded_photo();
    let version = agg.version;

    // Delete succeeds
    let events = agg
        .handle(
            DeletePhoto {
                id: agg.id,
                version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert!(agg.deleted_at.is_some());

    // Subsequent mutations are rejected
    let err = agg.handle(
        NormalizeOriginal {
            id: agg.id,
            new_size: 100,
            rotated: false,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::AlreadyDeleted)));

    let err = agg.handle(
        GenerateVariant {
            id: agg.id,
            variant: PhotoVariant::Thumb,
            size_bytes: 100,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::AlreadyDeleted)));

    let err = agg.handle(
        MarkVariantFailed {
            id: agg.id,
            variant: PhotoVariant::Thumb,
            error: "test".into(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::AlreadyDeleted)));

    let err = agg.handle(
        DeletePhoto {
            id: agg.id,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::AlreadyDeleted)));
}

#[test]
fn test_version_mismatch_rejected() {
    let agg = make_uploaded_photo();
    let wrong_version = AggregateVersion(0);

    let err = agg.handle(
        NormalizeOriginal {
            id: agg.id,
            new_size: 100,
            rotated: false,
            version: wrong_version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::VersionMismatch { .. })));

    let err = agg.handle(
        GenerateVariant {
            id: agg.id,
            variant: PhotoVariant::Thumb,
            size_bytes: 100,
            version: wrong_version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::VersionMismatch { .. })));

    let err = agg.handle(
        MarkVariantFailed {
            id: agg.id,
            variant: PhotoVariant::Thumb,
            error: "test".into(),
            version: wrong_version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::VersionMismatch { .. })));

    let err = agg.handle(
        DeletePhoto {
            id: agg.id,
            version: wrong_version,
        },
        make_ctx(),
    );
    assert!(matches!(err, Err(PhotoError::VersionMismatch { .. })));
}
