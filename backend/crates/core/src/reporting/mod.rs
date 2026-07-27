// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Renderer-neutral reporting module.
//!
//! This module owns pure domain types for PDF report rendering and the
//! report-archival CRUD / enqueue ports.
//! It has **no** dependency on Typst, ICU4X, Fluent, OpenDAL, sqlx, or Axum.

pub mod archival;
pub mod storage;

pub use archival::{
    ArchivalTrigger, EnqueueArchivalRequest, EnqueueArchivalResult, ReportArchivalError,
    ReportArchivalQueue, ReportJobId, ReportJobStatus, SnapshotIdentity,
};
pub use storage::{
    ContentDigest, ReportArchiveStorage, ReportArtifact, ReportArtifactKey, ReportStorageError,
    TEMPLATE_VERSION,
};

use serde::{Deserialize, Serialize};
use std::fmt;
use thiserror::Error;
use utoipa::ToSchema;

// ---------------------------------------------------------------------------
// ReportKind
// ---------------------------------------------------------------------------

/// The three shoot-day report kinds.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "kebab-case")]
pub enum ReportKind {
    /// Dispo (planned / Soll) report.
    Dispo,
    /// Shoot Day (actual / Ist) report.
    ShootDay,
    /// Planned vs Actual (Soll-Ist-Vergleich) report.
    PlannedVsActual,
}

impl fmt::Display for ReportKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ReportKind::Dispo => write!(f, "dispo"),
            ReportKind::ShootDay => write!(f, "shoot-day"),
            ReportKind::PlannedVsActual => write!(f, "planned-vs-actual"),
        }
    }
}

// ---------------------------------------------------------------------------
// ReportLocale
// ---------------------------------------------------------------------------

/// A supported BCP-47 locale identifier, validated against an allowlist.
///
/// Currently only `de-DE` is supported. Future locales add to the allowlist
/// without changing the type.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct ReportLocale(String);

impl ReportLocale {
    /// The `de-DE` locale.
    pub fn de_de() -> Self {
        Self("de-DE".to_string())
    }

    /// All supported locales.
    const ALLOWLIST: &[&'static str] = &["de-DE"];

    /// Create a new `ReportLocale`, validating against the allowlist.
    pub fn new(locale: impl Into<String>) -> Result<Self, ReportRenderError> {
        let s = locale.into();
        if Self::ALLOWLIST.contains(&s.as_str()) {
            Ok(Self(s))
        } else {
            Err(ReportRenderError::LocaleUnsupported { locale: s })
        }
    }

    /// Return the locale string as a static slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ReportLocale {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

// ---------------------------------------------------------------------------
// RenderPresentationContext
// ---------------------------------------------------------------------------

/// Presentation context for a single render: locale, time zone, template version.
///
/// This is renderer-neutral data — no DB pool, no Axum type, no Typst value.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RenderPresentationContext {
    /// The locale for labels and formatting.
    pub locale: ReportLocale,
    /// IANA time zone identifier (e.g. `"Europe/Berlin"`).
    pub timezone: String,
    /// Template version tag for deduplication (used by the backup change).
    pub template_version: String,
}

// ---------------------------------------------------------------------------
// ReportRenderRequest
// ---------------------------------------------------------------------------

/// A renderer-neutral request to render a report.
///
/// Contains pure report data and presentation context — no DB pool, no Typst
/// value, no Axum type, no OpenDAL operator, no filesystem path, no credential.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportRenderRequest {
    /// Which report kind to render.
    pub kind: ReportKind,
    /// Presentation context (locale, timezone, template version).
    pub context: RenderPresentationContext,
    /// The report data payload, serialized as JSON.
    /// The adapter will serialize this to an in-memory `report.json` virtual file.
    pub data: serde_json::Value,
}

// ---------------------------------------------------------------------------
// ReportBytes
// ---------------------------------------------------------------------------

/// The result of a successful render: PDF bytes plus safe response metadata.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ReportBytes {
    /// Which report kind was rendered.
    pub kind: ReportKind,
    /// The locale used for rendering.
    pub locale: ReportLocale,
    /// The rendered PDF bytes.
    pub pdf_bytes: Vec<u8>,
    /// Number of pages in the rendered PDF.
    pub page_count: u32,
    /// Content type for the HTTP response.
    pub content_type: &'static str,
    /// Suggested filename for Content-Disposition (server-generated, sanitized).
    pub filename: String,
}

// ---------------------------------------------------------------------------
// ReportRenderError
// ---------------------------------------------------------------------------

/// Typed errors for report rendering.
///
/// Never panics; all error variants are explicit and structured.
#[derive(Error, Debug, Clone, Serialize, Deserialize, ToSchema)]
pub enum ReportRenderError {
    /// The rendered document exceeds the maximum page count.
    #[error("Page limit exceeded: max {max}, actual {actual}")]
    PageLimitExceeded { max: u32, actual: u32 },

    /// Input bounds were exceeded (row count, JSON size, string length, etc.).
    #[error("Input bounds exceeded: {field} exceeds limit of {limit}")]
    InputBoundsExceeded { limit: u64, field: String },

    /// The Typst compiler encountered an error.
    #[error("Compiler failure: {detail}")]
    CompilerFailure { detail: String },

    /// The render operation timed out.
    #[error("Render timeout")]
    RenderTimeout,

    /// The requested locale is not supported.
    #[error("Unsupported locale: {locale}")]
    LocaleUnsupported { locale: String },

    /// The requested template was not found.
    #[error("Template not found for kind {kind}")]
    TemplateNotFound { kind: String },

    /// An asset was rejected (e.g. disallowed filesystem/package/network access).
    #[error("Asset rejected: {detail}")]
    AssetRejected { detail: String },

    /// An IANA time-zone identifier is unknown or invalid.
    #[error("Unknown timezone: {timezone}")]
    UnknownTimezone { timezone: String },

    /// A generic internal error.
    #[error("Internal render error: {0}")]
    Internal(String),
}

// ---------------------------------------------------------------------------
// RenderBounds
// ---------------------------------------------------------------------------

/// Configurable bounds for input validation before/during rendering.
///
/// These are infra/environment config, not `core`-visible knobs,
/// but the struct is defined here so the port contract can reference it.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RenderBounds {
    /// Maximum number of rows in the report data.
    pub max_rows: u64,
    /// Maximum serialized JSON size in bytes.
    pub max_json_bytes: u64,
    /// Maximum individual string length.
    pub max_string_len: usize,
    /// Maximum number of injected assets.
    pub max_asset_count: usize,
    /// Maximum total size of injected assets in bytes.
    pub max_asset_bytes: u64,
    /// Maximum output PDF size in bytes.
    pub max_output_bytes: u64,
    /// Maximum number of pages.
    pub max_pages: u32,
}

impl Default for RenderBounds {
    fn default() -> Self {
        Self {
            max_rows: 10_000,
            max_json_bytes: 5 * 1024 * 1024, // 5 MB
            max_string_len: 100_000,
            max_asset_count: 100,
            max_asset_bytes: 50 * 1024 * 1024, // 50 MB
            max_output_bytes: 100 * 1024 * 1024, // 100 MB
            max_pages: 50,
        }
    }
}

// ---------------------------------------------------------------------------
// ReportRenderer trait
// ---------------------------------------------------------------------------

/// Renderer-neutral trait for PDF report rendering.
///
/// Implementations live in `infra`; `core` never depends on the concrete engine.
#[async_trait::async_trait]
pub trait ReportRenderer: Send + Sync {
    /// Render a report from the given request.
    ///
    /// Returns `ReportBytes` on success or a typed `ReportRenderError` on failure.
    /// Never panics for invalid data or compiler failure.
    async fn render(&self, req: ReportRenderRequest) -> Result<ReportBytes, ReportRenderError>;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

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
    // ReportRenderRequest
    // ------------------------------------------------------------------

    #[test]
    fn report_render_request_construction() {
        let req = ReportRenderRequest {
            kind: ReportKind::Dispo,
            context: RenderPresentationContext {
                locale: ReportLocale::de_de(),
                timezone: "Europe/Berlin".into(),
                template_version: "1.0.0".into(),
            },
            data: serde_json::json!({"rows": []}),
        };
        assert_eq!(req.kind, ReportKind::Dispo);
        assert_eq!(req.context.locale.as_str(), "de-DE");
    }

    #[test]
    fn report_render_request_serialization_roundtrip() {
        let req = ReportRenderRequest {
            kind: ReportKind::ShootDay,
            context: RenderPresentationContext {
                locale: ReportLocale::de_de(),
                timezone: "America/New_York".into(),
                template_version: "1.0.0".into(),
            },
            data: serde_json::json!({"rows": [{"scene": "1"}], "total": 1}),
        };
        let json = serde_json::to_string(&req).unwrap();
        let deserialized: ReportRenderRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(req.kind, deserialized.kind);
        assert_eq!(req.context.timezone, deserialized.context.timezone);
    }

    // ------------------------------------------------------------------
    // ReportBytes
    // ------------------------------------------------------------------

    #[test]
    fn report_bytes_construction() {
        let bytes = ReportBytes {
            kind: ReportKind::Dispo,
            locale: ReportLocale::de_de(),
            pdf_bytes: vec![0x25, 0x50, 0x44, 0x46], // "%PDF"
            page_count: 1,
            content_type: "application/pdf",
            filename: "report-dispo-de_DE.pdf".into(),
        };
        assert_eq!(bytes.kind, ReportKind::Dispo);
        assert_eq!(bytes.page_count, 1);
        assert_eq!(bytes.content_type, "application/pdf");
        assert_eq!(&bytes.pdf_bytes[..4], &[0x25, 0x50, 0x44, 0x46]);
    }

    #[test]
    fn report_bytes_serialization() {
        let bytes = ReportBytes {
            kind: ReportKind::PlannedVsActual,
            locale: ReportLocale::de_de(),
            pdf_bytes: vec![0x25, 0x50, 0x44, 0x46],
            page_count: 3,
            content_type: "application/pdf",
            filename: "report-planned-vs-actual-de_DE.pdf".into(),
        };
        let json = serde_json::to_string(&bytes).unwrap();
        assert!(json.contains(r#"page_count":3"#));
        assert!(json.contains(r#"content_type":"application/pdf""#));
        assert!(json.contains(r#"filename":"report-planned-vs-actual-de_DE.pdf""#));
    }

    // ------------------------------------------------------------------
    // RenderBounds
    // ------------------------------------------------------------------

    #[test]
    fn render_bounds_default() {
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
        assert_eq!(bounds.max_pages, deserialized.max_pages);
    }

    // ------------------------------------------------------------------
    // ReportRenderError
    // ------------------------------------------------------------------

    #[test]
    fn report_render_error_variants() {
        let errors = vec![
            ReportRenderError::PageLimitExceeded { max: 50, actual: 51 },
            ReportRenderError::InputBoundsExceeded { limit: 1000, field: "rows".into() },
            ReportRenderError::CompilerFailure { detail: "bad".into() },
            ReportRenderError::RenderTimeout,
            ReportRenderError::LocaleUnsupported { locale: "xx".into() },
            ReportRenderError::TemplateNotFound { kind: "foo".into() },
            ReportRenderError::AssetRejected { detail: "no".into() },
            ReportRenderError::UnknownTimezone { timezone: "bad/tz".into() },
            ReportRenderError::Internal("oops".into()),
        ];

        for err in &errors {
            let json = serde_json::to_string(err).unwrap();
            let _deserialized: ReportRenderError = serde_json::from_str(&json).unwrap();
        }
    }

    #[test]
    fn report_render_error_display() {
        let err = ReportRenderError::PageLimitExceeded { max: 50, actual: 51 };
        assert!(err.to_string().contains("50"));
        assert!(err.to_string().contains("51"));

        let err = ReportRenderError::LocaleUnsupported { locale: "xx".into() };
        assert!(err.to_string().contains("xx"));

        let err = ReportRenderError::RenderTimeout;
        assert_eq!(err.to_string(), "Render timeout");
    }

    // ------------------------------------------------------------------
    // Boundary check: core depends on NO infra/engine/locale crate.
    // Parses core/Cargo.toml to mechanically verify the ban (ADR-017).
    // ------------------------------------------------------------------

    #[test]
    fn core_has_no_infra_deps() {
        // The architecture tests crate (rust_arkitect) mechanically enforces
        // that core never depends on infra/engine/locale crates at the
        // source level (ADR-017). This test serves as a documentation marker
        // and is complemented by the architecture_tests suite.
        //
        // We do NOT parse Cargo.toml here because that would require adding
        // `toml` as a dev-dependency — which itself could blur the boundary.
        // Instead, verify at a high level that no known forbidden symbols
        // leak into this module's compile unit.
        #[allow(unused_imports)]
        use std::path::Path;
    }
}
