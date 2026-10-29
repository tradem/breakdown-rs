// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::reporting::*;
use infra::reporting::locale::validate_timezone;
use infra::reporting::typst_renderer::{
    RenderConfig, RestrictedWorld, TypstReportRenderer, embedded_template_helpers,
    embedded_templates,
};
use std::collections::HashMap;
use typst::World;
use typst::syntax::{FileId, RootedPath, VirtualPath, VirtualRoot};

// ------------------------------------------------------------------
// validate_timezone
// ------------------------------------------------------------------

#[test]
fn test_validate_timezone_valid() {
    assert!(validate_timezone("Europe/Berlin").is_ok());
    assert!(validate_timezone("America/New_York").is_ok());
    assert!(validate_timezone("UTC").is_ok());
}

#[test]
fn test_validate_timezone_invalid() {
    assert!(validate_timezone("").is_err());
    assert!(validate_timezone("../etc/passwd").is_err());
    assert!(validate_timezone("/etc/passwd").is_err());
}

// ------------------------------------------------------------------
// RestrictedWorld
// ------------------------------------------------------------------

#[test]
fn restricted_world_denies_network() {
    let world = RestrictedWorld::new("test", b"{}", vec![]);

    // Network access should fail (no implementation)
    let network_id = FileId::new(RootedPath::new(
        VirtualRoot::Project,
        VirtualPath::new("http://example.com/data.json").unwrap(),
    ));
    assert!(world.file(network_id).is_err());
}

#[test]
fn restricted_world_denies_package_lookup() {
    let world = RestrictedWorld::new("test", b"{}", vec![]);

    // Package paths contain @version, e.g. "@preview/example/0.1.0/main.typ"
    let pkg_id = FileId::new(RootedPath::new(
        VirtualRoot::Project,
        VirtualPath::new("@preview/fontawesome/0.1.0/lib.typ").unwrap(),
    ));
    assert!(world.source(pkg_id).is_err());
    assert!(world.file(pkg_id).is_err());
}

#[test]
fn restricted_world_denies_host_fs_absolute_path() {
    let world = RestrictedWorld::new("test", b"{}", vec![]);

    // Absolute host FS paths should be denied
    let fs_id = FileId::new(RootedPath::new(
        VirtualRoot::Project,
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
fn with_defaults_renders_pdf_end_to_end_on_host_font_layout() {
    // Issue #642 end-to-end regression: on the failing host layout (fonts
    // only in subdirectories of the fontconfig trees — e.g. Arch), the
    // composition-root construction path must succeed and a render must
    // produce a real PDF. Skipped only when an *independent* probe (own
    // recursion, not the discovery code under test) confirms the host has no
    // font files at all — a discovery regression must fail this test, not
    // silently skip it (CodeRabbit review, PR #651).
    if !independent_host_font_probe() {
        eprintln!("host has no font files in the standard font trees; skipping e2e render");
        return;
    }
    let renderer =
        TypstReportRenderer::with_defaults().expect("with_defaults must succeed on a fonted host");
    assert!(
        !renderer.templates.is_empty(),
        "template map must be non-empty"
    );

    let req = ReportRenderRequest {
        kind: ReportKind::Dispo,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: "1.0.0".into(),
        },
        // Empty rows → the template's "Keine Daten vorhanden" branch — no
        // data coupling, only font + template + compiler must work.
        data: serde_json::json!({ "rows": [] }),
    };

    let rt = tokio::runtime::Runtime::new().unwrap();
    let rendered = rt
        .block_on(renderer.render(req))
        .expect("render must succeed");
    assert_eq!(rendered.content_type, "application/pdf");
    assert!(
        rendered.pdf_bytes.starts_with(b"%PDF"),
        "output must be a PDF"
    );
    assert!(rendered.page_count >= 1);
}

/// Independent font-presence probe for the e2e skip decision: a deliberately
/// simple second implementation (recursive read_dir + extension check over
/// the standard font trees; no symlink handling, no dedupe, no depth cap).
/// Deliberately does NOT reuse the discovery code under test.
fn independent_host_font_probe() -> bool {
    fn scan(dir: &std::path::Path, depth: usize) -> bool {
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

    let mut roots: Vec<std::path::PathBuf> = Vec::new();
    if let Some(home) = std::env::var_os("HOME").filter(|v| !v.is_empty()) {
        let home = std::path::PathBuf::from(home);
        roots.push(home.join(".local/share/fonts"));
        roots.push(home.join(".fonts"));
    }
    roots.push("/usr/share/fonts".into());
    roots.push("/usr/local/share/fonts".into());
    #[cfg(target_os = "macos")]
    {
        roots.push("/System/Library/Fonts".into());
        roots.push("/Library/Fonts".into());
    }
    roots.iter().any(|d| d.is_dir() && scan(d, 0))
}

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

// ---------------------------------------------------------------------------
// Issue #764: the template/data contract
//
// The templates build their table rows straight from the report JSON. Typst
// requires cells to be `content`, so a raw integer (`scene_number`,
// `notes.len()`) aborted compilation and every *non-empty* report answered an
// opaque HTTP 500. The tests below render every embedded template with
// representative row data on a deterministic font set, so a template/data
// contract break fails the suite instead of shipping.
// ---------------------------------------------------------------------------

/// Every report kind that has an embedded template.
const ALL_REPORT_KINDS: [ReportKind; 5] = [
    ReportKind::Dispo,
    ReportKind::ShootDay,
    ReportKind::PlannedVsActual,
    ReportKind::SeasonSollIst,
    ReportKind::EpisodeSollIst,
];

/// Fonts bundled with `typst-assets` (feature `fonts`).
///
/// The restricted world serves no host font files, and a probe-based skip would
/// silently disable the regression guard on fontless hosts. Bundled fonts make
/// the contract tests run everywhere, deterministically.
fn embedded_test_fonts() -> Vec<typst::text::Font> {
    typst_assets::fonts()
        .flat_map(|data| typst::text::Font::iter(typst::foundations::Bytes::new(data)))
        .collect()
}

fn de_context() -> RenderPresentationContext {
    RenderPresentationContext {
        locale: ReportLocale::de_de(),
        timezone: "Europe/Berlin".into(),
        template_version: "1.0.0".into(),
    }
}

/// Render `data` through the *embedded* template of `kind`.
fn render_embedded(kind: ReportKind, data: serde_json::Value) -> ReportBytes {
    let fonts = embedded_test_fonts();
    assert!(
        !fonts.is_empty(),
        "bundled `typst-assets` fonts must load — the contract tests must not be skippable"
    );
    let renderer = TypstReportRenderer::new(embedded_templates(), fonts);
    let req = ReportRenderRequest {
        kind,
        context: de_context(),
        data,
    };
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(renderer.render(req))
        .unwrap_or_else(|e| panic!("template `{kind}` must render row data: {e}"))
}

/// A representative payload per kind: a numbered scene and an unnumbered one,
/// a `null` `actual_order`, notes present/absent, every diff flag in both
/// states, and a German location containing `/ ( ) ·` (issue #764).
fn representative_rows(kind: ReportKind) -> serde_json::Value {
    let scene_id = "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e6f";
    let other_scene_id = "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e70";
    let shooting_day_id = "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e71";
    let other_day_id = "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e72";
    let location = "Tiefgarage / Klinikum (Stationscounter) · Ebene 3";

    match kind {
        ReportKind::Dispo => serde_json::json!({
            "rows": [
                {
                    "planned_order": "00000002",
                    "scene_id": scene_id,
                    "scene_number": 2,
                    "script_day": "Tag 1",
                    "location": location,
                    "mood": "I/T",
                    "summary": "Eine Szene."
                },
                {
                    "planned_order": "00000003",
                    "scene_id": other_scene_id,
                    "scene_number": null,
                    "script_day": null,
                    "location": null,
                    "mood": null,
                    "summary": null
                }
            ]
        }),
        ReportKind::ShootDay => serde_json::json!({
            "rows": [
                {
                    "actual_order": "00000003",
                    "scene_id": scene_id,
                    "scene_number": 2,
                    "script_day": "Tag 1",
                    "location": location,
                    "status": "Shot",
                    "start_dt": "2026-10-05T08:12:00Z",
                    "end_dt": "2026-10-05T09:40:00Z",
                    "notes": [
                        { "id": "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e73", "body": "Note A" }
                    ],
                    "continuity_photo_ids": []
                },
                {
                    // Raw integers independent of the scene number: a row with
                    // `notes.len() > 0` must not break the cell contract either.
                    "actual_order": null,
                    "scene_id": other_scene_id,
                    "scene_number": null,
                    "script_day": null,
                    "location": null,
                    "status": "Planned",
                    "start_dt": null,
                    "end_dt": null,
                    "notes": [
                        { "id": "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e74", "body": "Note B" },
                        { "id": "0199d3f2-6a4b-7c8d-9e0f-1a2b3c4d5e75", "body": "Note C" }
                    ],
                    "continuity_photo_ids": []
                }
            ]
        }),
        ReportKind::PlannedVsActual => serde_json::json!({
            "is_final": true,
            "rows": [
                {
                    "scene_id": scene_id,
                    "scene_number": 2,
                    "script_day": "Tag 1",
                    "location": location,
                    "planned_order": "00000002",
                    "actual_order": "00000003",
                    "moved": true,
                    "missing": false,
                    "skipped": false,
                    "reshot_candidate": false
                },
                {
                    "scene_id": other_scene_id,
                    "scene_number": null,
                    "script_day": null,
                    "location": null,
                    "planned_order": null,
                    "actual_order": null,
                    "moved": false,
                    "missing": true,
                    "skipped": true,
                    "reshot_candidate": true
                }
            ]
        }),
        ReportKind::SeasonSollIst | ReportKind::EpisodeSollIst => serde_json::json!({
            "is_final": false,
            "total_shooting_days": 2,
            "wrapped_shooting_days": 1,
            "rows": [
                {
                    "scene_id": scene_id,
                    "shooting_day_id": shooting_day_id,
                    "shooting_day_label": "Tag 1",
                    "scene_number": 2,
                    "script_day": "Tag 1",
                    "location": location,
                    "planned_order": "00000002",
                    "actual_order": "00000003",
                    "moved": true,
                    "missing": false,
                    "skipped": false,
                    "reshot_candidate": false
                },
                {
                    "scene_id": other_scene_id,
                    "shooting_day_id": other_day_id,
                    "shooting_day_label": null,
                    "scene_number": null,
                    "script_day": null,
                    "location": null,
                    "planned_order": null,
                    "actual_order": null,
                    "moved": false,
                    "missing": true,
                    "skipped": true,
                    "reshot_candidate": true
                }
            ]
        }),
    }
}

#[test]
fn every_template_renders_representative_rows_to_a_valid_pdf() {
    for kind in ALL_REPORT_KINDS {
        let rendered = render_embedded(kind, representative_rows(kind));
        assert_eq!(
            rendered.kind, kind,
            "template `{kind}` must report its own kind"
        );
        assert_eq!(rendered.content_type, "application/pdf");
        assert!(
            rendered.pdf_bytes.starts_with(b"%PDF-"),
            "template `{kind}` must produce a real PDF, got {} bytes",
            rendered.pdf_bytes.len()
        );
        assert!(
            rendered.page_count >= 1,
            "template `{kind}` must produce at least one page"
        );
    }
}

#[test]
fn template_cell_helper_normalises_every_json_scalar() {
    // `cell` is defined once in `_helpers.typ` and prepended to every
    // template (issue #764). Exercising it directly pins the convention the
    // templates rely on: `none` → empty cell, numbers/booleans → their Typst
    // repr, strings unchanged. Before the helper, `integer` and `boolean`
    // cells aborted compilation with `expected content, found …`.
    let template = format!(
        "{}\n#table(columns: 6, ..json(\"report.json\").cells.map(cell))",
        embedded_template_helpers()
    );
    let mut templates = HashMap::new();
    templates.insert(ReportKind::Dispo, template);
    let renderer = TypstReportRenderer::new(templates, embedded_test_fonts());
    let req = ReportRenderRequest {
        kind: ReportKind::Dispo,
        context: de_context(),
        data: serde_json::json!({
            "cells": [
                null,
                2,
                2.5,
                true,
                false,
                "Tiefgarage / Klinikum (Stationscounter) · Ebene 3"
            ]
        }),
    };
    let rt = tokio::runtime::Runtime::new().unwrap();
    let rendered = rt
        .block_on(renderer.render(req))
        .expect("cell() must normalise every JSON scalar into a table cell");
    assert!(rendered.pdf_bytes.starts_with(b"%PDF-"));
    assert!(rendered.page_count >= 1);
}

#[test]
fn embedded_templates_carry_the_shared_cell_helper() {
    let helpers = embedded_template_helpers();
    assert!(
        helpers.contains("#let cell("),
        "the shared helper snippet must define `cell`"
    );
    for (kind, source) in embedded_templates() {
        assert!(
            source.starts_with(helpers),
            "template `{kind}` must be prefixed with the shared helpers (issue #764)"
        );
        assert!(
            source.contains("cell(row."),
            "template `{kind}` must wrap its row cells in `cell(...)` (issue #764)"
        );
    }
}
