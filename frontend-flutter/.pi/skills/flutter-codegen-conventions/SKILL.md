---
name: flutter-codegen-conventions
description: Drive the breakdown-rs Flutter codegen stack — build_runner, freezed, json_serializable, riverpod_generator, drift_dev, openapi_generator. Use when regenerating or reviewing generated files; enforces the rebuild-only rule for lib/api/generated, .g.dart, .freezed.dart.
license: AGPL-3.0
compatibility: Requires Dart/Flutter SDK, `build_runner`, and (for the API client) `npx @openapitools/openapi-generator-cli`. The runtime deps + analysis_options land with the `scaffold-flutter-project` and `wire-openapi-dart-client` follow-ups.
metadata:
  author: breakdown-rs
  version: "1.0"
  provenance: |
    Portable subset described in upstream `dart-lang/skills` and
    `flutter/agent-plugins` (codegen conventions), adapted to breakdown-rs
    conventions. This SKILL.md is the authoritative breakdown-rs version.
    Upstream tracks the portable-subset structure; the rules below encode
    design.md §2 (generated vs hand-written) + §3 (OpenAPI contract) + §9
    (codegen conventions) and the `flutter-openapi-client` spec.
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Flutter Codegen Conventions

> **Provenance:** Ported from the portable subset described in upstream
> `dart-lang/skills` and `flutter/agent-plugins` (codegen conventions),
> adapted to breakdown-rs conventions. Authoritative source:
> `frontend-flutter/AGENTS.md` §2, §3, §9 and the `flutter-openapi-client`
> delta spec.

## The hard rule (rebuild-only)

**Generated files are read-only. Regenerate, never edit.** This is the
client-side twin of the backend's "never manually type API responses /
generated artifacts" rule. The directories/files below are rebuild-only:

| Generator | Output | Trigger |
|-----------|--------|---------|
| `openapi_generator` | `lib/api/generated/**` (pkg `breakdown_api`) | changes to `backend/openapi.yaml` |
| `drift_dev` | `*.g.dart` (Drift tables/queries) | schema/DAO edits |
| `riverpod_generator` | `*.g.dart` (providers) | `@riverpod` annotation edits |
| `freezed` | `*.freezed.dart` | `@freezed` model edits |
| `json_serializable` | `*.g.dart` (`fromJson`/`toJson`) | model field edits |

Hand-edits fail CI:
- The OpenAPI drift check regenerates into a throwaway and diffs against the
  committed tree (see `flutter-openapi-client` spec).
- `dart run build_runner build` is the single source for the `*.g.dart` /
  `*.freezed.dart` outputs.

## Regenerating the OpenAPI Dart client

The checked-in `backend/openapi.yaml` is the **single source of truth** for
the API surface (decision D1). Regenerate into `lib/api/generated/`:

```bash
cd frontend-flutter
npx @openapitools/openapi-generator-cli generate \
  -i ../backend/openapi.yaml \
  -g dart \
  -o lib/api/generated \
  --additional-properties=pubName=breakdown_api
```

- A PR that changes `backend/openapi.yaml` MUST regenerate the client and
  commit the diff in the same PR. CI's drift check fails otherwise.
- A PR that hand-edits anything under `lib/api/generated/` fails the same
  check — regenerate instead.
- Never consume a hand-typed API response type. Every API call's downstream is
  a generated DTO; mappers to domain entities live in `lib/data/` and are
  unit-tested in isolation (Tier 1).

## Running build_runner

```bash
cd frontend-flutter
dart run build_runner build --delete-conflicting-outputs
# watch mode during development:
dart run build_runner watch --delete-conflicting-outputs
```

- Always pass `--delete-conflicting-outputs` — never resolve a "conflicting
  output" by hand-editing a generated file; the generator owns it.
- Generated files are committed (not gitignored) so reviewers see codegen diffs
  in the PR, mirroring the backend's checked-in-artifact discipline.

## Per-generator conventions

### freezed (`*.freezed.dart`)
- Immutable value objects + sealed unions for domain state.
- `const` factories; `copyWith` for updates; never mutate.
- mappers from generated API DTOs → freezed domain entities live in
  `lib/data/mappers/` and are unit-tested.

### json_serializable (`*.g.dart`)
- Used on the freezed models for (de)serialization where the generated client
  needs it. Field renames via `@JsonSerializable(fieldRename: ...)`.
- Never `toJson`/`fromJson` a type that already has a generated DTO upstream —
  map instead.

### riverpod_generator (`*.g.dart`)
- Providers declared via `@riverpod` codegen; widgets consume via
  `ref.watch`/`ref.read`. **No hand-written `Provider` boilerplate** when
  codegen is available (decision D3 / `flutter-state-management`).
- Tests override via `ProviderContainer(overrides: [fooProvider.overrideWithValue(fake)])`
  — compile-safe, no service locator.

### drift_dev (`*.g.dart`)
- Drift mirrors the **read-projection DTOs**, never the event-store schema
  (`flutter-offline-scope` spec). Cache is a performance/offline-tolerance
  layer; it never holds state the server doesn't.
- A projection DTO shape change requires a **Drift migration in the same PR**
  so the cache never silently drops a field.

### openapi_generator (`lib/api/generated/**`)
- Package name `breakdown_api`. Resource-REST CQRS semantics — write = `POST`
  to resource/collection routes, read = `GET` to projection-backed routes
  (decision D2). NOT a `POST /commands/{aggregate}/{action}` command bus
  (corrects the ADR-007 sketch).
- The client treats the HTTP response as command acknowledgement (immediate);
  the eventual projection update is reconciled with an optimistic update +
  bounded-retry refetch (design.md §4), never by re-querying a second
  projection to "fill in" command context (client-side CQRS boundary).

## When codegen output looks wrong

- It is almost always a source annotation problem, not a generator bug. Fix the
  `@freezed`/`@riverpod`/`@DriftDatabase`/OpenAPI spec, then regenerate.
- If the generator genuinely needs a workaround, do **not** patch the output —
  open a change proposal and fix it at the source (spec / annotation /
  generator config).

## Review checklist

- [ ] No hand-edits under `lib/api/generated/` or any `*.g.dart` / `*.freezed.dart`?
- [ ] `backend/openapi.yaml` change accompanied by a regenerated client diff?
- [ ] `build_runner` run with `--delete-conflicting-outputs`?
- [ ] Drift table mirrors a read-projection DTO (not the event store)?
- [ ] DTO shape change shipped with a Drift migration?
- [ ] No hand-typed API response types consumed downstream of an API call?
