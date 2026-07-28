// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use breakdown_core::reporting::*;
use infra::reporting::locale::validate_timezone;
use infra::reporting::typst_renderer::{
    RenderConfig, RestrictedWorld, TypstReportRenderer,
};
use std::collections::HashMap;
use typst::syntax::{FileId, RootedPath, VirtualPath, VirtualRoot};
use typst::World;

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
fn render_config_defaults() {
    let config = RenderConfig::default();
    assert_eq!(config.concurrency_limit, 4);
    assert_eq!(config.deadline_secs, 30);
    assert_eq!(config.max_rows, 10_000);
    assert_eq!(config.max_json_bytes, 5 * 1024 * 1024);
    assert_eq!(config.max_output_bytes, 100 * 1024 * 1024);
    assert_eq!(config.max_pages, 50);
}
