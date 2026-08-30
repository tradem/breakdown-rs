---
name: flutter-lint-analysis
description: Apply and explain the breakdown-rs Flutter analyzer/lint rules. Use when writing or reviewing Dart in frontend-flutter/ to keep data/domain throw-free, surfaces Result discipline, and enforce theme/token + generated-file boundaries.
license: AGPL-3.0
compatibility: Requires the Flutter/Dart SDK and the project
  `breakdown_lints` analyzer-plugin package (built on `analysis_server_plugin`)
  for IDE/LSP enforcement, plus the `breakdown_lints_runner` custom lint runner
  for CI enforcement (issue #299).
metadata:
  author: breakdown-rs
  version: "1.1"
  provenance: |
    Portable subset described in upstream `flutter/agent-plugins` (lint/analysis
    guidance), adapted to breakdown-rs conventions. This SKILL.md is the
    authoritative breakdown-rs version; it maps to the `analysis_options.yaml`
    + a project `breakdown_lints` analyzer-plugin package (built on
    `analysis_server_plugin`) referenced in design.md §5/§6. Upstream
    tracks the portable-subset structure only — every rule below is the
    client-side twin of a backend hard rule, not a verbatim upstream copy.
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Flutter Lint & Analysis Guidance

> **Provenance:** Ported from the portable subset described in upstream
> `flutter/agent-plugins` (lint/analysis guidance), adapted to breakdown-rs
> conventions. The breakdown-rs `AGENTS.md` (§5 Security/Reliability, §6
> Testing, §9 Codegen) is the authoritative source; this skill operationalizes
> those rules into analyzer configuration + custom lint rule names.

## When to Use

- Scaffolding or editing `analysis_options.yaml` and the project
  `breakdown_lints` analyzer-plugin package (built on `analysis_server_plugin`,
  lands with the
  `scaffold-flutter-project` follow-up).
- Reviewing a PR under `frontend-flutter/**` for analyzer/lint compliance.
- Explaining *why* a given lint fires and how to fix it conventionally.

## Canonical analyzer baseline

`analysis_options.yaml` (created by the scaffold follow-up) extends the
`flutter_lints` / `lints` package and adds the `breakdown_lints`
  analyzer-plugin rules (built on `analysis_server_plugin`). The
rules below are the required set; the names are stable so `grep` and reviews
refer to them by id.

## Rule set (required)

### 1. `no_throw_in_data_domain`

The client-side twin of the backend's **"no panics in production code"** hard
rule (`unwrap`/`expect`/`panic` denied). Fallible operations in `lib/data/`
and `lib/domain/` MUST return `fpdart`'s `Result`/`Either` (or an equivalent
`Result` type) — errors are values. `throw` is only acceptable in:

- `lib/features/` widget assertion guards the framework already expects, and
- test code (`*_test.dart`).

Widgets/providers translate `Err` into `AsyncError` — never `throw` across the
data boundary. **Never** `throw` an exception to signal a domain failure
(`409`, `not found`, `validation`); return `Err(ProblemError(...))`.

```dart
// ✅ data/repository/season_repository.dart
TaskEither<ProblemError, SeasonDto> createSeason(CreateSeasonCommand cmd) =>
    _client.postSeasons(cmd.toRequest()).toTaskEither().map(SeasonDto.fromGenerated);

// ❌ forbidden
Future<SeasonDto> createSeason(CreateSeasonCommand cmd) async {
  if (cmd.name.isEmpty) throw ArgumentError('name'); // no throw in data/
}
```

### 2. `discard_result` (the backend `discard-result` twin)

Production code MUST NOT write the Dart equivalent of the backend's
`let _ = <fallible call>`. Concretely, each of these triggers the lint:

- an un-awaited `Future` (`someAsyncCall();` without `await` / without
  returning it),
- a discarded `Result`/`Either`/`TaskEither` (calling a fallible function and
  dropping the result),
- swallowing a `Future` returned from a function without surfacing its error.

Fix by one of:
- **propagate** (`return` it, or `await` and `?`-style via `.match`),
- **handle explicitly** (`await c.then((_) => ...)` or
  `if let Err(e) = ... { warn(...); }`-equivalent: `result.match((ok) => ..., (err) => log(...))`),
- **suppress with a justification** comment on the call line:
  `// lint-ignore: discard-result — fire-and-forget analytics, error logged upstream`
  (a justification comment MUST precede the directive, mirroring the backend
  rule).

### 3. `no_hardcoded_colors` / `no_hardcoded_text_styles`

Design tokens are the single source for colors, type, and spacing — they live
under `lib/design/` (see the `flutter-material3-theme` skill). Inline
`Color(0xFF...)`, `Colors.red`, `TextStyle(fontSize: 14)`, magic padding
constants in widgets are rejected. Use the theme extension / token classes.

### 4. `no_hand_edits_in_generated`

`vendor/breakdown_api/**` (package `breakdown_api`), `*.g.dart`, `*.freezed.dart`
are rebuild-only. Hand-edits fail the OpenAPI-drift / build_runner check in CI
(see `flutter-openapi-client` spec + `flutter-codegen-conventions` skill).
A hand-edit at the top of a generated file is the highest-severity finding.

### 5. `authz_gate_on_gated_calls` (structural review lint, see `flutter-client-authz`)

Every call to a handler-internal-authz-gated backend endpoint (photo upload,
photo byte fetch, photo delete, continuity-photo handlers) MUST be preceded by
a `// AUTHZ-GATE:` comment and a `currentMembershipProvider` check.
`grep AUTHZ-GATE` verification applies. (This one is review-enforced until the
`breakdown_lints` analyzer-plugin rule is implemented; see the
  `flutter-client-authz` spec.)

### 6. Standard `flutter_lints` strengthenings

- `avoid_print` (use `package:logging` via a provider) — error
- `prefer_const_constructors` — warn
- `require_trailing_commas` — warn (diff stability)
- `unawaited_futures` — **error** (overlaps `discard_result`)
- `use_super_parameters` — warn

## Applying a fix (workflow)

1. Run `flutter analyze` — note the rule id in the diagnostic.
2. Read the rule's "Fix by" above; pick the conventional remedy (propagate >
   handle > suppress-with-justification, in that order of preference).
3. For `discard_result`, prefer propagating the `Task`/`Result` up to the
   provider that can surface `AsyncError`; only suppress with a written
   justification when the call is genuinely fire-and-forget and its error is
   logged elsewhere.
4. For `no_hand_edits_in_generated`, regenerate — never edit:
   ```bash
   cd frontend-flutter
   npx @openapitools/openapi-generator-cli generate \
     -i ../backend/openapi.yaml -g dart -o vendor/breakdown_api \
     --additional-properties=pubName=breakdown_api
   dart run build_runner build --delete-conflicting-outputs
   ```
5. Re-run `flutter analyze`; ensure zero new diagnostics before commit.

## CI posture

The `breakdown_lints` analyzer-plugin package uses `analysis_server_plugin`,
which only loads inside the analysis server (IDE/LSP mode). The batch
`dart analyze` / `flutter analyze` CLI does **not** load plugins (issue #299).

To enforce the custom rules in CI, a **custom lint runner**
(`tool/breakdown_lints_runner`) re-implements the same four rules using the
`analyzer` package directly. CI runs both:

1. `flutter analyze` — enforces standard analyzer/lint rules
2. Custom lint runner — enforces the four custom rules:
   ```bash
   cd tool/breakdown_lints_runner
   dart pub get
   dart run bin/run_lints.dart ../..
   ```

The `analysis_options.yaml > analyzer > errors` block configures severities
for IDE/LSP mode. The `unrecognized_error_code: ignore` entry suppresses
warnings about the custom codes in the batch CLI.
