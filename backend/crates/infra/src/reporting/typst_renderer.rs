// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! In-process Typst adapter implementing `ReportRenderer`.
//!
//! Uses a restricted virtual filesystem that only serves embedded templates
//! and the in-memory `report.json` data file. Host FS, network, and package
//! access are denied.

use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

use breakdown_core::reporting::{
    ReportBytes, ReportKind, ReportRenderError, ReportRenderRequest, ReportRenderer,
};
use typst::diag::FileError;
use typst::foundations::Bytes;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::Font;
use typst::{LibraryExt, World};
use typst_layout::PagedDocument;
use typst_pdf::PdfOptions;

/// Template content embedded at compile time.
#[allow(dead_code)]
struct EmbeddedTemplate {
    source: String,
}

/// A restricted virtual filesystem for Typst compilation.
///
/// Only serves:
/// - The main template file (`.typ`)
/// - The `report.json` data file
/// - Embedded fonts
///
/// Denies all host FS, network, and package access.
pub struct RestrictedWorld {
    /// The main template source code.
    template_source: Source,
    /// The report data as JSON bytes.
    report_json: Bytes,
    /// Embedded fonts.
    fonts: Vec<Font>,
    /// Font book metadata.
    #[allow(dead_code)]
    font_book: typst::utils::LazyHash<typst::text::FontBook>,
    /// The standard library.
    library: typst::utils::LazyHash<typst::Library>,
}

impl RestrictedWorld {
    /// Create a new restricted world with the given template and data.
    #[allow(clippy::unwrap_used)] // VirtualPath::new from a const literal cannot fail
    pub fn new(template_source: &str, report_json: &[u8], fonts: Vec<Font>) -> Self {
        let file_id = FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("main.typ").unwrap(), // const-time path literal
        ));
        let source = Source::new(file_id, template_source.to_string());

        let mut font_book = typst::text::FontBook::new();
        for font in &fonts {
            font_book.push(font.info().clone());
        }

        Self {
            template_source: source,
            report_json: Bytes::new(report_json.to_vec()),
            fonts,
            font_book: typst::utils::LazyHash::new(font_book),
            library: typst::utils::LazyHash::new(typst::Library::default()),
        }
    }
}

impl RestrictedWorld {
    /// Return the FileId for the virtual `report.json`.
    #[allow(clippy::unwrap_used)] // VirtualPath::new from a const literal cannot fail
    fn report_json_id(&self) -> FileId {
        FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("report.json").unwrap(),
        ))
    }
}

impl World for RestrictedWorld {
    fn library(&self) -> &typst::utils::LazyHash<typst::Library> {
        &self.library
    }

    fn book(&self) -> &typst::utils::LazyHash<typst::text::FontBook> {
        &self.font_book
    }

    fn main(&self) -> FileId {
        self.template_source.id()
    }

    fn source(&self, id: FileId) -> Result<Source, FileError> {
        // Only allow the main template file
        if id == self.template_source.id() {
            Ok(self.template_source.clone())
        } else {
            Err(FileError::NotFound(std::path::PathBuf::from("denied")))
        }
    }

    fn file(&self, id: FileId) -> Result<Bytes, FileError> {
        // Only allow reading report.json
        if id == self.report_json_id() {
            Ok(self.report_json.clone())
        } else {
            Err(FileError::NotFound(std::path::PathBuf::from("denied")))
        }
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn today(
        &self,
        _offset: Option<typst::foundations::Duration>,
    ) -> Option<typst::foundations::Datetime> {
        // Pin to a fixed date for deterministic rendering
        #[allow(clippy::unwrap_used)] // const-time ymd
        Some(typst::foundations::Datetime::from_ymd(2024, 6, 15).unwrap())
    }
}

/// Configuration for bounded rendering.
#[derive(Debug, Clone)]
pub struct RenderConfig {
    /// Maximum number of concurrent renders (semaphore size).
    pub concurrency_limit: usize,
    /// Wall-clock deadline in seconds.
    pub deadline_secs: u64,
    /// Maximum number of rows in the report data.
    pub max_rows: u64,
    /// Maximum serialized JSON size in bytes.
    pub max_json_bytes: u64,
    /// Maximum output PDF size in bytes.
    pub max_output_bytes: u64,
    /// Maximum number of pages.
    pub max_pages: u32,
}

impl Default for RenderConfig {
    fn default() -> Self {
        Self {
            concurrency_limit: 4,
            deadline_secs: 30,
            max_rows: 10_000,
            max_json_bytes: 5 * 1024 * 1024,     // 5 MB
            max_output_bytes: 100 * 1024 * 1024, // 100 MB
            max_pages: 50,
        }
    }
}

/// In-process Typst renderer for PDF reports.
pub struct TypstReportRenderer {
    /// Embedded templates keyed by report kind.
    pub templates: HashMap<ReportKind, String>,
    /// Embedded fonts for deterministic Latin text rendering.
    fonts: Vec<Font>,
    /// Font book metadata.
    #[allow(dead_code)]
    font_book: typst::utils::LazyHash<typst::text::FontBook>,
    /// Semaphore for concurrency control.
    semaphore: Arc<tokio::sync::Semaphore>,
    /// Render configuration.
    pub config: RenderConfig,
}

impl fmt::Debug for TypstReportRenderer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TypstReportRenderer")
            .field("templates", &self.templates.len())
            .field("fonts", &self.fonts.len())
            .field("semaphore", &self.semaphore)
            .field("config", &self.config)
            .finish_non_exhaustive()
    }
}

impl TypstReportRenderer {
    /// Create a new renderer with embedded templates and fonts.
    ///
    /// # Arguments
    /// * `templates` - Map from report kind to template source code
    /// * `fonts` - Pre-loaded fonts for rendering
    pub fn new(templates: HashMap<ReportKind, String>, fonts: Vec<Font>) -> Self {
        Self::with_config(templates, fonts, RenderConfig::default())
    }

    /// Create a new renderer with custom configuration.
    pub fn with_config(
        templates: HashMap<ReportKind, String>,
        fonts: Vec<Font>,
        config: RenderConfig,
    ) -> Self {
        let mut font_book = typst::text::FontBook::new();
        for font in &fonts {
            font_book.push(font.info().clone());
        }

        let semaphore = Arc::new(tokio::sync::Semaphore::new(config.concurrency_limit));

        Self {
            templates,
            fonts,
            font_book: typst::utils::LazyHash::new(font_book),
            semaphore,
            config,
        }
    }

    /// Create a renderer with default embedded templates and system fonts.
    ///
    /// This is a convenience constructor for development and testing.
    /// In production, use `new()` with explicitly embedded templates and fonts.
    pub fn with_defaults() -> Result<Self, ReportRenderError> {
        let mut templates = HashMap::new();

        // Embed templates at compile time via include_str!
        templates.insert(
            ReportKind::Dispo,
            include_str!("../../templates/reports/dispo.typ").to_string(),
        );
        templates.insert(
            ReportKind::ShootDay,
            include_str!("../../templates/reports/shoot-day.typ").to_string(),
        );
        templates.insert(
            ReportKind::PlannedVsActual,
            include_str!("../../templates/reports/planned-vs-actual.typ").to_string(),
        );

        // Load system fonts
        let fonts = load_system_fonts().map_err(ReportRenderError::Internal)?;

        Ok(Self::new(templates, fonts))
    }
}

#[async_trait::async_trait]
impl ReportRenderer for TypstReportRenderer {
    async fn render(&self, req: ReportRenderRequest) -> Result<ReportBytes, ReportRenderError> {
        // Acquire semaphore permit
        let _permit = self
            .semaphore
            .acquire()
            .await
            .map_err(|_| ReportRenderError::Internal("Semaphore closed".into()))?;

        // Look up template
        let template_source =
            self.templates
                .get(&req.kind)
                .ok_or_else(|| ReportRenderError::TemplateNotFound {
                    kind: req.kind.to_string(),
                })?;

        // Serialize report data
        let report_json_vec = serde_json::to_vec(&req.data)
            .map_err(|e| ReportRenderError::Internal(format!("JSON serialization failed: {e}")))?;

        // Check input bounds: JSON size
        if report_json_vec.len() > self.config.max_json_bytes as usize {
            return Err(ReportRenderError::InputBoundsExceeded {
                limit: self.config.max_json_bytes,
                field: "report_json_bytes".into(),
            });
        }

        // Create restricted world
        let world = RestrictedWorld::new(template_source, &report_json_vec, self.fonts.clone());

        // Compile with deadline
        let deadline = std::time::Duration::from_secs(self.config.deadline_secs);
        let compile_result = tokio::time::timeout(deadline, async {
            tokio::task::spawn_blocking(move || {
                let warned = typst::compile::<PagedDocument>(&world);
                warned.output.map_err(|diagnostics| {
                    let details: Vec<String> =
                        diagnostics.iter().map(|d| d.message.to_string()).collect();
                    ReportRenderError::CompilerFailure {
                        detail: details.join("; "),
                    }
                })
            })
            .await
            .map_err(|_| ReportRenderError::Internal("Task join failed".into()))?
        })
        .await
        .map_err(|_| ReportRenderError::RenderTimeout)?;

        let document = compile_result?;

        // Check page limit
        let page_count = document.pages().len() as u32;
        if page_count > self.config.max_pages {
            return Err(ReportRenderError::PageLimitExceeded {
                max: self.config.max_pages,
                actual: page_count,
            });
        }

        // Export to PDF
        let pdf_bytes =
            typst_pdf::pdf(&document, &PdfOptions::default()).map_err(|diagnostics| {
                let details: Vec<String> =
                    diagnostics.iter().map(|d| d.message.to_string()).collect();
                ReportRenderError::CompilerFailure {
                    detail: format!("PDF export failed: {}", details.join("; ")),
                }
            })?;

        // Check output size bound
        if pdf_bytes.len() > self.config.max_output_bytes as usize {
            return Err(ReportRenderError::InputBoundsExceeded {
                limit: self.config.max_output_bytes,
                field: "output_pdf_bytes".into(),
            });
        }

        // Build safe filename
        let filename = format!(
            "report-{}-{}.pdf",
            req.kind,
            req.context.locale.as_str().replace('-', "_")
        );

        Ok(ReportBytes {
            kind: req.kind,
            locale: req.context.locale.clone(),
            pdf_bytes,
            page_count,
            content_type: "application/pdf",
            filename,
        })
    }
}

/// Load system fonts for development/testing.
///
/// In production, fonts should be explicitly embedded.
fn load_system_fonts() -> Result<Vec<Font>, String> {
    let mut fonts = Vec::new();

    // Common system font directories
    let font_dirs = [
        "/usr/share/fonts",
        "/usr/local/share/fonts",
        "/System/Library/Fonts",
        #[cfg(target_os = "windows")]
        "C:\\Windows\\Fonts",
    ];

    for dir in &font_dirs {
        let path = std::path::Path::new(dir);
        if path.exists()
            && let Ok(entries) = std::fs::read_dir(path)
        {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("ttf")
                    && let Ok(data) = std::fs::read(&path)
                {
                    let bytes = typst::foundations::Bytes::new(data);
                    let fonts_iter = Font::iter(bytes);
                    fonts.extend(fonts_iter);
                }
            }
        }
    }

    if fonts.is_empty() {
        return Err("No system fonts found".into());
    }

    Ok(fonts)
}
