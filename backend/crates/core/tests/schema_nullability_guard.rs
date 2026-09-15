// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Guard test against the `value_type`-drops-`Option`-nullability lie
//! (issue #423).
//!
//! A bare `#[schema(value_type = String)]` override on an `Option<T>` field
//! makes utoipa emit a **required, non-nullable** property even though the
//! runtime serializes `None` as JSON `null`. The generated Dart client
//! (dart-dio/built_value) then faithfully declares non-nullable fields and its
//! deserializer throws `null as String` on every response carrying an unset
//! value — the characters list was unusable for every freshly created
//! character because of exactly this lie.
//!
//! The OpenAPI drift check cannot catch this class of bug: both sides of the
//! drift (checked-in schema and runtime serialization) derive from the same
//! Rust attribute. This test instead asserts the *rendered utoipa schema*
//! directly: every `Option<…>` field must render as nullable (`type: [T,
//! null]`) and must not appear in the schema's `required` list.

#![allow(clippy::unwrap_used, clippy::expect_used)] // test code (AGENTS.md §3)

use breakdown_core::block::commands::{CreateBlock, UpdateBlockTimeSpan};
use breakdown_core::block::views::BlockView;
use breakdown_core::character::events::CharacterMeasurements;
use serde_json::{Map, Value};
use utoipa::ToSchema;

/// Render a struct's component schema as JSON.
fn schema_of<T: ToSchema + 'static>() -> Map<String, Value> {
    let ref_or_schema = T::schema();
    let json = serde_json::to_value(&ref_or_schema).expect("schema serializes to JSON");
    // All guarded structs are inline schemas (no registered component name);
    // unwrap the RefOr wrapper if utoipa emitted one.
    assert!(
        json.get("$ref").is_none(),
        "schema of {} unexpectedly emitted a $ref",
        std::any::type_name::<T>()
    );
    json.as_object()
        .cloned()
        .expect("schema of {T} is a JSON object")
}

/// Assert every property of `schema` is nullable unless it is declared with an
/// explicit `nullable: false` marker, and that no property listed in
/// `required` was produced from an `Option` (all `Option` fields here are
/// tracked by name).
fn assert_nullable(schema: &Map<String, Value>, owner: &str, required_properties: &[&str]) {
    let properties = schema
        .get("properties")
        .expect("schema has properties")
        .as_object()
        .expect("properties are an object");
    let required: Vec<&str> = schema
        .get("required")
        .and_then(|r| r.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
        .unwrap_or_default();

    for name in required_properties {
        let prop = properties
            .get(*name)
            .expect("rendered schema must contain the tracked `Option` property {name} of {owner}");
        let type_field = prop.get("type").cloned().unwrap_or(Value::Null);
        // utoipa renders `Option<T>` as the JSON-Schema 2020-12 style
        // `type: [T, "null"]` — accept the scalar `nullable: true` form too.
        let nullable = match &type_field {
            Value::Array(types) => types.iter().any(|t| t == "null"),
            _ => prop.get("nullable").map(|n| n == "true").unwrap_or(false),
        };
        assert!(
            nullable,
            "property `{name}` of {owner} is not nullable in the rendered schema \
             (type: {type_field:?}) — a `value_type` override on an `Option` \
             field drops nullability and breaks the generated Dart client \
             (issue #423)"
        );
        if required_properties.contains(name) {
            assert!(
                !required.contains(name),
                "property `{name}` of {owner} is required in the rendered schema — \
                 an `Option` field must be optional (issue #423)"
            );
        }
    }
}

/// The seven measurement fields are `Option<Decimal>`: a freshly created
/// character serializes all of them as JSON `null` — the schema must be
/// nullable and optional, or the generated client crashes on every character
/// list read (issue #423, live bug).
#[test]
fn character_measurements_schema_is_nullable_and_optional() {
    let schema = schema_of::<CharacterMeasurements>();
    assert_nullable(
        &schema,
        "CharacterMeasurements",
        &[
            "shoe_size",
            "hat_size",
            "height",
            "weight",
            "chest",
            "waist",
            "hips",
        ],
    );
}

/// `BlockView.start_date`/`end_date` are `Option<NaiveDate>`: currently
/// harmless only because every existing block carries both dates — a block
/// without dates would break `GET /v1/blocks` parsing the same way (issue
/// #423, pending crash class).
#[test]
fn block_view_schema_dates_are_nullable_and_optional() {
    let schema = schema_of::<BlockView>();
    assert_nullable(&schema, "BlockView", &["start_date", "end_date"]);
}

/// Command payloads: client-side request construction with `null` for an
/// omitted time span would fail against a required non-nullable property the
/// same way (issue #423).
#[test]
fn block_command_schemas_dates_are_nullable_and_optional() {
    let create = schema_of::<CreateBlock>();
    assert_nullable(&create, "CreateBlock", &["start_date", "end_date"]);
    let update = schema_of::<UpdateBlockTimeSpan>();
    assert_nullable(&update, "UpdateBlockTimeSpan", &["start_date", "end_date"]);
}
