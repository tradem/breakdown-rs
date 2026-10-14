// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.3 (neuralwatt)

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
        let templates = embedded_templates();
        // Load system fonts — a failure here is a deployment misconfiguration
        // (the composition root fails fast on it, issue #642).
        let fonts = load_system_fonts().map_err(ReportRenderError::Internal)?;

        Ok(Self::new(templates, fonts))
    }
}

/// The compile-time embedded report templates, keyed by report kind.
fn embedded_templates() -> HashMap<ReportKind, String> {
    let mut templates = HashMap::new();

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
    templates.insert(
        ReportKind::SeasonSollIst,
        include_str!("../../templates/reports/season-soll-ist.typ").to_string(),
    );
    templates.insert(
        ReportKind::EpisodeSollIst,
        include_str!("../../templates/reports/episode-soll-ist.typ").to_string(),
    );

    templates
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

/// Font file extensions accepted by the discovery walk (lowercase).
///
/// TrueType (`ttf`), OpenType (`otf`), TrueType/OpenType collections
/// (`ttc`/`otc`). Typst's `Font::iter` parses any of these containers and
/// yields one font per face in the file.
const FONT_EXTENSIONS: [&str; 4] = ["ttf", "otf", "ttc", "otc"];

/// Maximum recursion depth of the font-directory walk.
///
/// Font trees on real distros are 2–3 levels deep (`/usr/share/fonts/<family>/
/// <file>.ttf`); 8 leaves ample headroom while bounding pathological layouts
/// and deep symlink chains.
const FONT_WALK_MAX_DEPTH: usize = 8;

/// Environment variable for an explicit font-directory override (issue #642
/// review: NixOS et al. keep fonts in fontconfig-configured package paths
/// outside the XDG/fixed system trees). Value is an OS path list
/// (`:`-separated on Unix, `;` on Windows), `~`-expansion applied; entries
/// take precedence over every automatic discovery source.
const REPORT_FONT_DIRS_ENV: &str = "REPORT_FONT_DIRS";

/// The fontconfig configuration files parsed for `<dir>` entries
/// (best-effort — see [`fontconfig_config_dirs`]).
const FONTCONFIG_CONFIG_FILES: [&str; 2] = ["/etc/fonts/fonts.conf", "/etc/fonts/local.conf"];

/// Extract `<dir ...>path</dir>` entries from a fontconfig XML snippet
/// (pure text scan — no XML dependency; `fonts.conf` is a controlled,
/// machine-managed file).
///
/// Returns `(prefix, raw_path)` pairs; `prefix` is the optional `prefix`
/// attribute ("default", "xdg", "config", "fontconfig"). `<cachedir>` and
/// any other element is ignored.
fn fontconfig_dir_entries(config: &str) -> Vec<(Option<String>, String)> {
    let mut entries = Vec::new();
    let mut rest = config;
    while let Some(start) = rest.find("<dir") {
        let after_tag = &rest[start + 4..];
        // Must be the actual `dir` element (not `<dirfoo`).
        let opens = after_tag
            .chars()
            .next()
            .is_some_and(|c| c == '>' || c == ' ' || c == '/' || c == '\t' || c == '\n');
        if !opens {
            rest = after_tag;
            continue;
        }
        let Some(tag_end_rel) = after_tag.find('>') else {
            break;
        };
        let attrs = &after_tag[..tag_end_rel];
        let after_attrs = &after_tag[tag_end_rel + 1..];
        let Some(close_rel) = after_attrs.find("</dir>") else {
            break;
        };
        let raw = after_attrs[..close_rel].trim();
        let prefix = attrs.split("prefix=").nth(1).and_then(|rest| {
            let rest = rest.trim_start();
            let quote = rest.chars().next()?;
            if quote != '"' && quote != '\'' {
                return None;
            }
            rest[1..].split(quote).next().map(str::to_string)
        });
        if !raw.is_empty() {
            entries.push((prefix, raw.to_string()));
        }
        rest = &after_attrs[close_rel + 6..];
    }
    entries
}

/// Resolve one fontconfig `<dir>` entry to a filesystem path (pure; the
/// env-reading wrapper is [`resolve_fontconfig_entry`]).
///
/// Handles the `prefix` attribute ("default", "xdg", "config",
/// "fontconfig"), `~`-expansion, and the `${XDG_DATA_HOME}` /
/// `${XDG_CONFIG_HOME}` / `${HOME}` variable substitutions fontconfig's
/// shipped configs use. Entries whose variables are unset resolve to `None`
/// (fontconfig would ignore them too). Unknown variable references skip the
/// entry rather than guessing.
fn resolve_fontconfig_entry_with(
    prefix: Option<&str>,
    raw: &str,
    config_dir: &std::path::Path,
    home: Option<&std::path::Path>,
    xdg_data_home: Option<&std::path::Path>,
    xdg_config_home: Option<&std::path::Path>,
) -> Option<std::path::PathBuf> {
    // Substitute the shipped-config variables.
    let mut resolved = raw.to_string();
    for (var, value) in [
        ("XDG_DATA_HOME", xdg_data_home),
        ("XDG_CONFIG_HOME", xdg_config_home),
        ("HOME", home),
    ] {
        let needle = format!("${{{var}}}");
        if resolved.contains(&needle) {
            let value = value?;
            resolved = resolved.replace(&needle, &value.to_string_lossy());
        }
    }
    if resolved.contains("${") {
        // Unknown variable reference — best-effort discovery skips it.
        return None;
    }

    let mut path = match prefix {
        Some("xdg") => {
            let base = xdg_data_home
                .map(std::borrow::ToOwned::to_owned)
                .or_else(|| home.map(|h| h.join(".local/share")))?;
            base.join(resolved)
        }
        Some("config") => config_dir.join(resolved),
        Some("fontconfig") => {
            let base = xdg_config_home
                .map(std::borrow::ToOwned::to_owned)
                .or_else(|| home.map(|h| h.join(".config")))?;
            base.join("fontconfig").join(resolved)
        }
        // "default" or unknown prefix: path as-is (fontconfig default).
        _ => std::path::PathBuf::from(resolved),
    };

    // `~`-expansion (fontconfig allows `~/.fonts` style entries).
    if let Ok(relative) = path.strip_prefix("~") {
        let home = home?;
        path = home.join(relative);
    }

    Some(path)
}

/// Env-reading wrapper around [`resolve_fontconfig_entry_with`].
fn resolve_fontconfig_entry(
    prefix: Option<&str>,
    raw: &str,
    config_dir: &std::path::Path,
) -> Option<std::path::PathBuf> {
    let env_path = |key: &str| {
        std::env::var_os(key)
            .filter(|v| !v.is_empty())
            .map(std::path::PathBuf::from)
    };
    resolve_fontconfig_entry_with(
        prefix,
        raw,
        config_dir,
        env_path("HOME").as_deref(),
        env_path("XDG_DATA_HOME").as_deref(),
        env_path("XDG_CONFIG_HOME").as_deref(),
    )
}

/// Best-effort parse of the fontconfig configuration for `<dir>` entries
/// (issue #642 review: NixOS and friends point fontconfig at font packages
/// outside the XDG/fixed system trees).
///
/// This is deliberately *not* a full fontconfig implementation: only the two
/// well-known config files are scanned for literal `<dir>` elements —
/// `<include>` chains and advanced variable semantics are out of scope.
/// Hosts with exotic setups use the [`REPORT_FONT_DIRS_ENV`] override, which
/// always wins.
fn fontconfig_config_dirs() -> Vec<std::path::PathBuf> {
    let mut dirs = Vec::new();
    for file in FONTCONFIG_CONFIG_FILES {
        let Ok(config) = std::fs::read_to_string(file) else {
            continue;
        };
        let config_dir = std::path::Path::new(file)
            .parent()
            .unwrap_or(std::path::Path::new("/"));
        for (prefix, raw) in fontconfig_dir_entries(&config) {
            if let Some(dir) = resolve_fontconfig_entry(prefix.as_deref(), &raw, config_dir) {
                dirs.push(dir);
            }
        }
    }
    dirs
}

/// Explicit font-directory override from [`REPORT_FONT_DIRS_ENV`]
/// (OS path list; `~`-expanded; entries take precedence over all
/// automatic discovery sources).
fn override_font_dirs() -> Vec<std::path::PathBuf> {
    let Some(value) = std::env::var_os(REPORT_FONT_DIRS_ENV).filter(|v| !v.is_empty()) else {
        return Vec::new();
    };
    let home = std::env::var_os("HOME")
        .filter(|v| !v.is_empty())
        .map(std::path::PathBuf::from);
    std::env::split_paths(&value)
        .filter(|p| !p.as_os_str().is_empty())
        .map(|p| {
            // Expand a leading `~` for service-file convenience.
            match (&home, p.strip_prefix("~")) {
                (Some(home), Ok(relative)) => home.join(relative),
                _ => p,
            }
        })
        .collect()
}

/// Candidate font directories per the freedesktop/fontconfig convention plus
/// the platform defaults, deduplicated, later duplicates ignored.
///
/// Order (first wins for dedupe):
/// 1. `$REPORT_FONT_DIRS` explicit override (issue #642 review)
/// 2. fontconfig-configured `<dir>` entries from `/etc/fonts/fonts.conf`
///    and `/etc/fonts/local.conf` (best-effort)
/// 3. `$XDG_DATA_HOME/fonts` (default `$HOME/.local/share/fonts`) and every
///    `$XDG_DATA_DIRS/<dir>/fonts` (defaults: `/usr/local/share`, `/usr/share`)
/// 4. Legacy `$HOME/.fonts`
/// 5. The unconditional system trees — containers frequently run without
///    `$HOME`, and distros always ship `/usr/share/fonts`
/// 6. macOS / Windows platform font directories
fn candidate_font_dirs() -> Vec<std::path::PathBuf> {
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    let mut push = |dir: std::path::PathBuf| {
        if !dirs.contains(&dir) && dir.is_dir() {
            dirs.push(dir);
        }
    };

    // --- explicit override (issue #642 review: NixOS et al.) ---
    for dir in override_font_dirs() {
        push(dir);
    }
    // --- fontconfig-managed directories ---
    for dir in fontconfig_config_dirs() {
        push(dir);
    }

    // --- freedesktop base-directory spec (Linux/BSD) ---
    if let Some(data_home) = std::env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME")
                .filter(|v| !v.is_empty())
                .map(|home| std::path::PathBuf::from(home).join(".local/share"))
        })
    {
        push(data_home.join("fonts"));
    }
    let data_dirs = std::env::var_os("XDG_DATA_DIRS")
        .filter(|v| !v.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("/usr/local/share:/usr/share"));
    for dir in std::env::split_paths(&data_dirs) {
        push(dir.join("fonts"));
    }
    if let Some(home) = std::env::var_os("HOME").filter(|v| !v.is_empty()) {
        push(std::path::PathBuf::from(home).join(".fonts"));
    }

    // --- unconditional system trees (containers, service users) ---
    push(std::path::PathBuf::from("/usr/share/fonts"));
    push(std::path::PathBuf::from("/usr/local/share/fonts"));

    // --- platform defaults ---
    #[cfg(target_os = "macos")]
    {
        push(std::path::PathBuf::from("/System/Library/Fonts"));
        push(std::path::PathBuf::from("/Library/Fonts"));
    }
    #[cfg(target_os = "windows")]
    {
        if let Some(windir) = std::env::var_os("SystemRoot").filter(|v| !v.is_empty()) {
            push(std::path::PathBuf::from(windir).join("Fonts"));
        }
    }

    dirs
}

/// Recursively collect font files under `dir` (depth-capped).
///
/// Accepts `ttf`/`otf`/`ttc`/`otc` (case-insensitive), follows symlinks to
/// *files*, and deliberately does **not** descend into symlinked directories
/// (cycle safety — a depth cap alone cannot distinguish a font farm from a
/// loop). Unreadable entries are skipped; discovery is best-effort by design.
fn collect_font_files_in_dir(dir: &std::path::Path, depth: usize) -> Vec<std::path::PathBuf> {
    let mut found = Vec::new();
    if depth > FONT_WALK_MAX_DEPTH {
        return found;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return found;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = std::fs::metadata(&path) else {
            continue; // broken symlink or raced removal — skip
        };
        if meta.is_dir() {
            // Do not descend into symlinked directories (cycle safety).
            if entry.file_type().is_ok_and(|ft| !ft.is_symlink()) {
                found.extend(collect_font_files_in_dir(&path, depth + 1));
            }
        } else if meta.is_file()
            && let Some(ext) = path.extension().and_then(|e| e.to_str())
            && FONT_EXTENSIONS.contains(&ext.to_ascii_lowercase().as_str())
        {
            found.push(path);
        }
    }
    found
}

/// Collect the deduplicated set of font files across all candidate dirs.
fn collect_font_files(dirs: &[std::path::PathBuf]) -> Vec<std::path::PathBuf> {
    let mut seen = std::collections::HashSet::new();
    let mut files = Vec::new();
    for dir in dirs {
        for path in collect_font_files_in_dir(dir, 0) {
            // Canonicalize so XDG overlap (`$XDG_DATA_DIRS` containing
            // `/usr/share` next to the unconditional `/usr/share/fonts`)
            // loads every font exactly once.
            if let Ok(canonical) = path.canonicalize()
                && seen.insert(canonical)
            {
                files.push(path);
            }
        }
    }
    files
}

/// Load system fonts via freedesktop/fontconfig-convention discovery.
///
/// Recurses into subdirectories (distro font trees are rarely flat) and
/// accepts `ttf`/`otf`/`ttc`/`otc`. Returns an error — never a silent empty
/// set — when no fonts can be found, so the composition root can fail fast
/// (issue #642).
fn load_system_fonts() -> Result<Vec<Font>, String> {
    let dirs = candidate_font_dirs();
    if dirs.is_empty() {
        return Err(
            "no font directories found — install fonts (fontconfig-style tree under \
             /usr/share/fonts, or point REPORT_FONT_DIRS at font directories) \
             so PDF reports can render"
                .into(),
        );
    }

    let mut fonts = Vec::new();
    for file in collect_font_files(&dirs) {
        if let Ok(data) = std::fs::read(&file) {
            let bytes = typst::foundations::Bytes::new(data);
            fonts.extend(Font::iter(bytes));
        }
    }

    if fonts.is_empty() {
        return Err(format!(
            "no usable fonts found in {} candidate director{} — PDF reports \
             cannot render; install fonts (fontconfig-style tree under \
             /usr/share/fonts) or set REPORT_FONT_DIRS to font directories",
            dirs.len(),
            if dirs.len() == 1 { "y" } else { "ies" }
        ));
    }

    Ok(fonts)
}

// --- P4.4 mutation-hardening: `Debug for TypstReportRenderer` guard ---
//
// Kills the `replace <impl fmt::Debug for TypstReportRenderer>::fmt ->
// fmt::Result with Ok(Default::default())` mutant (empty output). Constructing
// with empty templates/fonts needs no system fonts, so this is a fast
// whitebox kill. The remaining P4.4 typst mutants (`font`, `render` bound
// checks, `load_system_fonts`) are excluded in `.cargo/mutants.toml` (they only
// change behaviour when an actual Typst compile runs, which requires system
// fonts — a system resource, per the `CommandsImpl>::` precedent).
#[cfg(test)]
mod mutation_tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn debug_impl_is_non_empty() {
        let renderer = TypstReportRenderer::new(HashMap::new(), vec![]);
        let s = format!("{renderer:?}");
        assert!(
            !s.is_empty(),
            "Debug for TypstReportRenderer must not be empty"
        );
        assert!(
            s.contains("TypstReportRenderer"),
            "Debug for TypstReportRenderer must identify the type"
        );
    }
}

// --- Issue #642: font discovery + non-empty-renderer invariant ---
#[cfg(test)]
mod font_discovery_tests {
    // Test code: filesystem scaffolding needs expect(); an invariant failure
    // reports via panic!/eprintln! (AGENTS.md §3: test code may allow these
    // with justification).
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        clippy::print_stderr
    )]

    use super::*;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};

    /// Unique temp directory (no `tempfile` dev-dependency in infra).
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let n = COUNTER.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "bkd-642-{}-{}-{}",
                label,
                std::process::id(),
                n
            ));
            std::fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            // Best-effort temp cleanup in a test helper — a leftover temp dir
            // under std::env::temp_dir is harmless; panic-landing in Drop
            // would mask the real test failure.
            // ast-grep-ignore: discard-result
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn touch(dir: &Path, name: &str) -> PathBuf {
        let p = dir.join(name);
        if let Some(parent) = p.parent() {
            std::fs::create_dir_all(parent).expect("create parent");
        }
        std::fs::write(&p, b"not-a-real-font-but-the-walker-only-paths").expect("write file");
        p
    }

    fn relative_names(root: &Path, files: &[PathBuf]) -> Vec<String> {
        let mut names: Vec<String> = files
            .iter()
            .map(|p| {
                p.strip_prefix(root)
                    .expect("file under root")
                    .to_string_lossy()
                    .into_owned()
            })
            .collect();
        names.sort();
        names
    }

    #[test]
    fn recurses_into_subdirectories() {
        let tmp = TempDir::new("recurse");
        touch(tmp.path(), "a/font.ttf");
        touch(tmp.path(), "a/b/c/deep.otf");
        let found = collect_font_files_in_dir(tmp.path(), 0);
        assert_eq!(
            relative_names(tmp.path(), &found),
            vec!["a/b/c/deep.otf", "a/font.ttf"]
        );
    }

    #[test]
    fn accepts_ttf_otf_ttc_otc_case_insensitive() {
        let tmp = TempDir::new("ext");
        for name in ["x.TTF", "y.Otf", "z.ttc", "w.OTC", "v.TtF"] {
            touch(tmp.path(), name);
        }
        let found = collect_font_files_in_dir(tmp.path(), 0);
        assert_eq!(found.len(), 5, "all five case variants must be collected");
    }

    #[test]
    fn ignores_non_font_files() {
        let tmp = TempDir::new("ignore");
        touch(tmp.path(), "README.txt");
        touch(tmp.path(), "font.pfb");
        touch(tmp.path(), "noext");
        touch(tmp.path(), "archive.zip");
        let found = collect_font_files_in_dir(tmp.path(), 0);
        assert!(
            found.is_empty(),
            "non-font files must be ignored, got {found:?}"
        );
    }

    #[cfg(unix)]
    #[test]
    fn follows_file_symlinks_but_not_symlinked_directories() {
        let tmp = TempDir::new("symlink");
        let real = touch(tmp.path(), "real/RealFont.ttf");
        std::os::unix::fs::symlink(&real, tmp.path().join("link.ttf"))
            .expect("create file symlink");
        // A symlinked directory that would loop back onto the root if followed.
        std::os::unix::fs::symlink(tmp.path(), tmp.path().join("loop"))
            .expect("create dir symlink");

        let found = collect_font_files_in_dir(tmp.path(), 0);
        let names = relative_names(tmp.path(), &found);
        assert!(
            names.contains(&"link.ttf".to_string()),
            "file symlink must be followed, got {names:?}"
        );
        assert!(
            names.contains(&"real/RealFont.ttf".to_string()),
            "real nested font must be found, got {names:?}"
        );
        assert_eq!(
            names.len(),
            2,
            "symlinked directory must not be descended into (loop guard), got {names:?}"
        );
    }

    #[test]
    fn depth_cap_bounds_the_walk() {
        let tmp = TempDir::new("depth");
        // Build a chain of FONT_WALK_MAX_DEPTH + 2 nested directories; the
        // font at the deepest level (depth > cap) must not be reached, the
        // font at the cap boundary must be.
        let mut deep = tmp.path().to_path_buf();
        for i in 0..(FONT_WALK_MAX_DEPTH + 2) {
            deep = deep.join(format!("d{i}"));
        }
        std::fs::create_dir_all(&deep).expect("create deep chain");
        std::fs::write(deep.join("too-deep.ttf"), b"x").expect("write deep font");

        let mut boundary = tmp.path().to_path_buf();
        for i in 0..FONT_WALK_MAX_DEPTH {
            boundary = boundary.join(format!("d{i}"));
        }
        std::fs::create_dir_all(&boundary).expect("create boundary chain");
        std::fs::write(boundary.join("boundary.ttf"), b"x").expect("write boundary font");

        let found = collect_font_files_in_dir(tmp.path(), 0);
        let mut prefix = (0..FONT_WALK_MAX_DEPTH)
            .map(|i| format!("d{i}"))
            .collect::<Vec<_>>()
            .join("/");
        prefix.push_str("/boundary.ttf");
        assert_eq!(
            relative_names(tmp.path(), &found),
            vec![prefix],
            "depth cap must exclude fonts deeper than {FONT_WALK_MAX_DEPTH} levels"
        );
    }

    #[test]
    fn duplicate_candidate_dirs_are_deduplicated() {
        let tmp = TempDir::new("dedupe");
        touch(tmp.path(), "f.ttf");
        let dirs = vec![tmp.path().to_path_buf(), tmp.path().to_path_buf()];
        let found = collect_font_files(&dirs);
        assert_eq!(
            found.len(),
            1,
            "same file via two candidate dirs must load once"
        );
    }

    #[test]
    fn embedded_templates_cover_all_report_kinds() {
        // Non-empty-renderer invariant (issue #642): the composition root must
        // never be able to wire a renderer without templates.
        let templates = embedded_templates();
        for kind in [
            ReportKind::Dispo,
            ReportKind::ShootDay,
            ReportKind::PlannedVsActual,
            ReportKind::SeasonSollIst,
            ReportKind::EpisodeSollIst,
        ] {
            let src = templates
                .get(&kind)
                .unwrap_or_else(|| panic!("embedded template for {kind:?} must exist"));
            assert!(
                !src.is_empty(),
                "embedded template for {kind:?} must be non-empty"
            );
        }
    }

    #[test]
    fn with_defaults_yields_nonempty_renderer_on_fonted_hosts() {
        // The full invariant from the issue: on a host whose font layout the
        // discovery understands (subdirectories included — this host is
        // exactly the failing Arch layout from the issue), `with_defaults`
        // must succeed and produce a non-empty template map AND a non-empty
        // font book. Skipped only on genuinely fontless hosts — determined by
        // an *independent* probe (own recursion, deliberately not
        // `collect_font_files`), so a discovery regression fails this test
        // instead of silently skipping it (CodeRabbit review, PR #651).
        let dirs = candidate_font_dirs();
        if !independent_font_probe(&dirs) {
            eprintln!("host has no discoverable fonts; skipping with_defaults invariant");
            return;
        }
        let renderer = TypstReportRenderer::with_defaults()
            .expect("with_defaults must succeed when fonts are discoverable");
        assert!(
            !renderer.templates.is_empty(),
            "template map must be non-empty"
        );
        assert!(!renderer.fonts.is_empty(), "font book must be non-empty");
    }

    /// Independent font-presence probe: a deliberately simple second
    /// implementation (recursive read_dir + extension check, no symlinks,
    /// no dedupe, no depth cap) used only to decide whether the host has
    /// font files at all. Must never be used to drive production logic.
    fn independent_font_probe(dirs: &[std::path::PathBuf]) -> bool {
        fn scan(dir: &Path, depth: usize) -> bool {
            if depth > 12 {
                return false;
            }
            let Ok(entries) = std::fs::read_dir(dir) else {
                return false;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                let Ok(meta) = std::fs::metadata(&path) else {
                    continue;
                };
                if meta.is_dir() && scan(&path, depth + 1) {
                    return true;
                }
                if meta.is_file()
                    && let Some(ext) = path.extension().and_then(|e| e.to_str())
                    && matches!(
                        ext.to_ascii_lowercase().as_str(),
                        "ttf" | "otf" | "ttc" | "otc"
                    )
                {
                    return true;
                }
            }
            false
        }
        dirs.iter().any(|d| scan(d, 0))
    }

    // --- fontconfig `<dir>` parsing / resolution (pure, env-free) ---

    #[test]
    fn fontconfig_parses_dir_entries_and_skips_other_elements() {
        let config = "\
            <?xml version=\"1.0\"?>
            <!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">
            <fontconfig>
              <dir>/usr/share/fonts</dir>
              <dir prefix=\"xdg\">fonts</dir>
              <dir>~/.fonts</dir>
              <cachedir>/var/cache/fontconfig</cachedir>
              <dirignore-me>/opt/trap</dirignore-me>
              <dir prefix='config'>conf.d/fonts</dir>
              <dir>${XDG_DATA_HOME}/fonts</dir>
            </fontconfig>";
        let entries = fontconfig_dir_entries(config);
        let raws: Vec<&str> = entries.iter().map(|(_, raw)| raw.as_str()).collect();
        assert_eq!(
            raws,
            vec![
                "/usr/share/fonts",
                "fonts",
                "~/.fonts",
                "conf.d/fonts",
                "${XDG_DATA_HOME}/fonts"
            ]
        );
        assert_eq!(entries[1].0.as_deref(), Some("xdg"));
        assert_eq!(entries[3].0.as_deref(), Some("config"));
        assert_eq!(entries[0].0, None);
    }

    #[test]
    fn fontconfig_resolution_handles_prefixes_tilde_and_variables() {
        let home = Path::new("/home/u");
        let xdg_data = Path::new("/xdg/data");
        let xdg_config = Path::new("/xdg/config");
        let config_dir = Path::new("/etc/fonts");
        let resolve = |prefix: Option<&str>, raw: &str| {
            resolve_fontconfig_entry_with(
                prefix,
                raw,
                config_dir,
                Some(home),
                Some(xdg_data),
                Some(xdg_config),
            )
        };

        assert_eq!(
            resolve(None, "/usr/share/fonts"),
            Some(PathBuf::from("/usr/share/fonts"))
        );
        assert_eq!(
            resolve(Some("xdg"), "fonts"),
            Some(PathBuf::from("/xdg/data/fonts"))
        );
        assert_eq!(
            resolve(Some("config"), "conf.d/fonts"),
            Some(PathBuf::from("/etc/fonts/conf.d/fonts"))
        );
        assert_eq!(
            resolve(Some("fontconfig"), "d"),
            Some(PathBuf::from("/xdg/config/fontconfig/d"))
        );
        assert_eq!(
            resolve(None, "~/.fonts"),
            Some(PathBuf::from("/home/u/.fonts"))
        );
        assert_eq!(
            resolve(None, "${XDG_DATA_HOME}/fonts"),
            Some(PathBuf::from("/xdg/data/fonts"))
        );
        // Unset HOME: `~`-entry cannot resolve.
        assert_eq!(
            resolve_fontconfig_entry_with(None, "~/.fonts", config_dir, None, None, None),
            None
        );
        // Unknown variable reference: skipped, never guessed.
        assert_eq!(resolve(None, "${NIX_STORE}/fonts"), None);
    }
}
