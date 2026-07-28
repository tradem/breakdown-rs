// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use breakdown_core::reporting::*;

// ------------------------------------------------------------------
// ReportKind
// ------------------------------------------------------------------

#[test]
fn report_kind_display() {
    assert_eq!(ReportKind::Dispo.to_string(), "dispo");
    assert_eq!(ReportKind::ShootDay.to_string(), "shoot-day");
    assert_eq!(ReportKind::PlannedVsActual.to_string(), "planned-vs-actual");
}

#[test]
fn report_kind_serialization_roundtrip() {
    let kinds = vec![
        ReportKind::Dispo,
        ReportKind::ShootDay,
        ReportKind::PlannedVsActual,
    ];
    for kind in &kinds {
        let json = serde_json::to_string(kind).unwrap();
        let deserialized: ReportKind = serde_json::from_str(&json).unwrap();
        assert_eq!(*kind, deserialized);
    }
}

#[test]
fn report_kind_from_str_roundtrip() {
    assert_eq!(
        serde_json::from_str::<ReportKind>("\"dispo\"").unwrap(),
        ReportKind::Dispo
    );
    assert_eq!(
        serde_json::from_str::<ReportKind>("\"shoot-day\"").unwrap(),
        ReportKind::ShootDay
    );
    assert_eq!(
        serde_json::from_str::<ReportKind>("\"planned-vs-actual\"").unwrap(),
        ReportKind::PlannedVsActual
    );
}

// ------------------------------------------------------------------
// ReportLocale
// ------------------------------------------------------------------

#[test]
fn report_locale_allowlist() {
    assert_eq!(ReportLocale::de_de().as_str(), "de-DE");
    assert!(ReportLocale::new("de-DE").is_ok());
    assert!(ReportLocale::new("en-US").is_err());
    assert!(ReportLocale::new("../etc/passwd").is_err());
    assert!(ReportLocale::new("").is_err());
}

#[test]
fn report_locale_error_is_unsupported() {
    let err = ReportLocale::new("fr-FR").unwrap_err();
    assert!(matches!(err, ReportRenderError::LocaleUnsupported { .. }));
}

#[test]
fn report_locale_display() {
    assert_eq!(ReportLocale::de_de().to_string(), "de-DE");
    assert_eq!(ReportLocale::new("de-DE").unwrap().to_string(), "de-DE");
}

#[test]
fn report_locale_serialization_roundtrip() {
    let locale = ReportLocale::de_de();
    let json = serde_json::to_string(&locale).unwrap();
    assert_eq!(json, "\"de-DE\"");
    let deserialized: ReportLocale = serde_json::from_str(&json).unwrap();
    assert_eq!(locale, deserialized);
}

// ------------------------------------------------------------------
// RenderPresentationContext
// ------------------------------------------------------------------

#[test]
fn render_presentation_context_construction() {
    let ctx = RenderPresentationContext {
        locale: ReportLocale::de_de(),
        timezone: "Europe/Berlin".into(),
        template_version: "1.0.0".into(),
    };
    assert_eq!(ctx.locale.as_str(), "de-DE");
    assert_eq!(ctx.timezone, "Europe/Berlin");
    assert_eq!(ctx.template_version, "1.0.0");
}

#[test]
fn render_presentation_context_serialization_roundtrip() {
    let ctx = RenderPresentationContext {
        locale: ReportLocale::de_de(),
        timezone: "Europe/Berlin".into(),
        template_version: "1.0.0".into(),
    };
    let json = serde_json::to_string(&ctx).unwrap();
    let deserialized: RenderPresentationContext = serde_json::from_str(&json).unwrap();
    assert_eq!(ctx.locale, deserialized.locale);
    assert_eq!(ctx.timezone, deserialized.timezone);
    assert_eq!(ctx.template_version, deserialized.template_version);
}

// ------------------------------------------------------------------
// RenderBounds
// ------------------------------------------------------------------

#[test]
fn render_bounds_default_values() {
    let bounds = RenderBounds::default();
    assert_eq!(bounds.max_rows, 10_000);
    assert_eq!(bounds.max_json_bytes, 5 * 1024 * 1024);
    assert_eq!(bounds.max_string_len, 100_000);
    assert_eq!(bounds.max_asset_count, 100);
    assert_eq!(bounds.max_asset_bytes, 50 * 1024 * 1024);
    assert_eq!(bounds.max_output_bytes, 100 * 1024 * 1024);
    assert_eq!(bounds.max_pages, 50);
}

#[test]
fn render_bounds_serialization_roundtrip() {
    let bounds = RenderBounds::default();
    let json = serde_json::to_string(&bounds).unwrap();
    let deserialized: RenderBounds = serde_json::from_str(&json).unwrap();
    assert_eq!(bounds.max_rows, deserialized.max_rows);
    assert_eq!(bounds.max_json_bytes, deserialized.max_json_bytes);
    assert_eq!(bounds.max_string_len, deserialized.max_string_len);
    assert_eq!(bounds.max_asset_count, deserialized.max_asset_count);
    assert_eq!(bounds.max_asset_bytes, deserialized.max_asset_bytes);
    assert_eq!(bounds.max_output_bytes, deserialized.max_output_bytes);
    assert_eq!(bounds.max_pages, deserialized.max_pages);
}

// ------------------------------------------------------------------
// ReportRenderError
// ------------------------------------------------------------------

#[test]
fn report_render_error_display() {
    let err = ReportRenderError::PageLimitExceeded { max: 50, actual: 51 };
    assert!(err.to_string().contains("50"));
    assert!(err.to_string().contains("51"));

    let err = ReportRenderError::LocaleUnsupported { locale: "fr-FR".into() };
    assert!(err.to_string().contains("fr-FR"));

    let err = ReportRenderError::TemplateNotFound { kind: "dispo".into() };
    assert!(err.to_string().contains("dispo"));
}

#[test]
fn report_render_error_serialization_roundtrip() {
    let errors = vec![
        ReportRenderError::PageLimitExceeded { max: 50, actual: 51 },
        ReportRenderError::InputBoundsExceeded { limit: 1000, field: "rows".into() },
        ReportRenderError::CompilerFailure { detail: "test".into() },
        ReportRenderError::RenderTimeout,
        ReportRenderError::LocaleUnsupported { locale: "fr-FR".into() },
        ReportRenderError::TemplateNotFound { kind: "dispo".into() },
        ReportRenderError::AssetRejected { detail: "test".into() },
        ReportRenderError::UnknownTimezone { timezone: "Invalid".into() },
        ReportRenderError::Internal("test".into()),
    ];
    for err in &errors {
        let json = serde_json::to_string(err).unwrap();
        let _deserialized: ReportRenderError = serde_json::from_str(&json).unwrap();
        // Just verify it deserializes without error
    }
}
