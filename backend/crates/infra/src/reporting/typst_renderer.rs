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
struct RestrictedWorld {
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
    fn new(template_source: &str, report_json: &[u8], fonts: Vec<Font>) -> Self {
        let file_id = FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("main.typ").unwrap(),
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
    templates: HashMap<ReportKind, String>,
    /// Embedded fonts for deterministic Latin text rendering.
    fonts: Vec<Font>,
    /// Font book metadata.
    #[allow(dead_code)]
    font_book: typst::utils::LazyHash<typst::text::FontBook>,
    /// Semaphore for concurrency control.
    semaphore: Arc<tokio::sync::Semaphore>,
    /// Render configuration.
    config: RenderConfig,
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
        let fonts = load_system_fonts().map_err(|e| ReportRenderError::Internal(e))?;

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
        if path.exists() {
            if let Ok(entries) = std::fs::read_dir(path) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().and_then(|e| e.to_str()) == Some("ttf") {
                        if let Ok(data) = std::fs::read(&path) {
                            let bytes = typst::foundations::Bytes::new(data);
                            let fonts_iter = Font::iter(bytes);
                            fonts.extend(fonts_iter);
                        }
                    }
                }
            }
        }
    }

    if fonts.is_empty() {
        return Err("No system fonts found".into());
    }

    Ok(fonts)
}

#[cfg(test)]
mod tests {
    use super::*;
    use breakdown_core::reporting::RenderPresentationContext;
    use breakdown_core::reporting::ReportLocale;

    // ------------------------------------------------------------------
    // RestrictedWorld isolation tests
    // ------------------------------------------------------------------

    #[test]
    fn restricted_world_denies_unknown_files() {
        let world = RestrictedWorld::new("test", b"{}", vec![]);

        // Unknown file should fail
        let unknown_id = FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("unknown.typ").unwrap(),
        ));
        assert!(world.source(unknown_id).is_err());
    }

    #[test]
    fn restricted_world_serves_main_template() {
        let world = RestrictedWorld::new("= Hello", b"{}", vec![]);

        // Main template should work
        assert!(world.source(world.main()).is_ok());
    }

    #[test]
    fn restricted_world_serves_report_json() {
        let world = RestrictedWorld::new("test", b"{\"key\": \"value\"}", vec![]);

        // report.json should work
        assert!(world.file(world.report_json_id()).is_ok());
    }

    #[test]
    fn restricted_world_denies_network() {
        let world = RestrictedWorld::new("test", b"{}", vec![]);

        // Network access should fail (no implementation)
        let network_id = FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("http://example.com/data.json").unwrap(),
        ));
        assert!(world.file(network_id).is_err());
    }

    #[test]
    fn restricted_world_denies_package_lookup() {
        let world = RestrictedWorld::new("test", b"{}", vec![]);

        // Package paths contain @version, e.g. "@preview/example/0.1.0/main.typ"
        let pkg_id = FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("@preview/fontawesome/0.1.0/lib.typ").unwrap(),
        ));
        assert!(world.source(pkg_id).is_err());
        assert!(world.file(pkg_id).is_err());
    }

    #[test]
    fn restricted_world_denies_host_fs_absolute_path() {
        let world = RestrictedWorld::new("test", b"{}", vec![]);

        // Absolute host FS paths should be denied
        let fs_id = FileId::new(typst::syntax::RootedPath::new(
            typst::syntax::VirtualRoot::Project,
            VirtualPath::new("/etc/passwd").unwrap(),
        ));
        assert!(world.source(fs_id).is_err());
        assert!(world.file(fs_id).is_err());
    }

    #[test]
    fn restricted_world_fixed_today() {
        let world = RestrictedWorld::new("test", b"{}", vec![]);

        let dt = world.today(None).unwrap();
        // Should return the fixed date (2024-06-15) as set in the implementation
        assert_eq!(
            dt,
            typst::foundations::Datetime::from_ymd(2024, 6, 15).unwrap()
        );
    }

    // ------------------------------------------------------------------
    // TypstReportRenderer construction tests
    // ------------------------------------------------------------------

    #[test]
    fn typst_report_renderer_new() {
        let mut templates = HashMap::new();
        templates.insert(ReportKind::Dispo, "= Test".to_string());
        let renderer = TypstReportRenderer::new(templates.clone(), vec![]);
        assert_eq!(renderer.config.max_pages, 50);
        assert_eq!(renderer.config.concurrency_limit, 4);
        assert!(renderer.templates.contains_key(&ReportKind::Dispo));
    }

    #[test]
    fn typst_report_renderer_with_config() {
        let mut templates = HashMap::new();
        templates.insert(ReportKind::ShootDay, "= Test".to_string());
        let config = RenderConfig {
            max_pages: 10,
            concurrency_limit: 2,
            deadline_secs: 5,
            ..Default::default()
        };
        let renderer = TypstReportRenderer::with_config(templates, vec![], config.clone());
        assert_eq!(renderer.config.max_pages, 10);
        assert_eq!(renderer.config.concurrency_limit, 2);
        assert_eq!(renderer.config.deadline_secs, 5);
    }

    #[test]
    fn typst_report_renderer_template_not_found() {
        // No templates registered at all
        let renderer = TypstReportRenderer::new(HashMap::new(), vec![]);

        let req = ReportRenderRequest {
            kind: ReportKind::Dispo,
            context: RenderPresentationContext {
                locale: ReportLocale::de_de(),
                timezone: "Europe/Berlin".into(),
                template_version: "1.0.0".into(),
            },
            data: serde_json::json!({}),
        };

        let rt = tokio::runtime::Runtime::new().unwrap();
        let result = rt.block_on(renderer.render(req));
        assert!(matches!(
            result,
            Err(ReportRenderError::TemplateNotFound { .. })
        ));
    }

    // ------------------------------------------------------------------
    // Input bounds tests
    // ------------------------------------------------------------------

    #[test]
    fn typst_report_renderer_rejects_oversized_json() {
        let mut templates = HashMap::new();
        templates.insert(ReportKind::Dispo, "= Test".to_string());
        let config = RenderConfig {
            max_json_bytes: 10, // Very small limit
            ..Default::default()
        };
        let renderer = TypstReportRenderer::with_config(templates, vec![], config);

        let req = ReportRenderRequest {
            kind: ReportKind::Dispo,
            context: RenderPresentationContext {
                locale: ReportLocale::de_de(),
                timezone: "Europe/Berlin".into(),
                template_version: "1.0.0".into(),
            },
            data: serde_json::json!({"data": "this is way more than 10 bytes of JSON data"}),
        };

        let rt = tokio::runtime::Runtime::new().unwrap();
        let result = rt.block_on(renderer.render(req));
        assert!(matches!(
            result,
            Err(ReportRenderError::InputBoundsExceeded { .. })
        ));
    }

    // ------------------------------------------------------------------
    // RenderConfig defaults
    // ------------------------------------------------------------------

    #[test]
    fn render_config_defaults() {
        let config = RenderConfig::default();
        assert_eq!(config.concurrency_limit, 4);
        assert_eq!(config.deadline_secs, 30);
        assert_eq!(config.max_rows, 10_000);
        assert_eq!(config.max_json_bytes, 5 * 1024 * 1024);
        assert_eq!(config.max_output_bytes, 100 * 1024 * 1024);
        assert_eq!(config.max_pages, 50);
    }
}
