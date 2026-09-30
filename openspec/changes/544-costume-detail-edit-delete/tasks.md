<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Tasks: Costume details are editable and deletable (issue #544)

## 1. Core — event, command, aggregate
- [ ] `crates/core/src/costume/events.rs`: `CostumeEvent::DetailUpdated { id, detail, version }` + `event_type()` arm
- [ ] `crates/core/src/costume/commands.rs`: `UpdateCostumeDetail { id, detail, series_id, version }` + `CommandName`
- [ ] `crates/core/src/costume/error.rs`: `DetailNotFound { id }`
- [ ] `crates/core/src/costume/aggregate.rs`: `Apply` arm (in-place `Update`, order preserved) + `impl Command<UpdateCostumeDetail>` (version fence → `DetailNotFound` → event)
- [ ] `RemoveDetail` emits `DetailNotFound` instead of `ValidationError("Detail not found")`
- [ ] `crates/core/src/costume/ports.rs`: `update_detail`
- [ ] `crates/core/src/error.rs`: `DetailNotFound` → `DomainError::NotFound`
- [ ] `crates/core/src/error_registry.rs`: `COSTUME_DETAIL_NOT_FOUND` (404, extension `id`)
- [ ] Core tests: update success / not-found (no event) / version chain; `RemoveDetail` 404 variant; detail order in `details` stable across an update

## 2. Infra
- [ ] `command_adapters.rs`: `update_detail`
- [ ] `projectors/costume.rs`: `DetailUpdated` arm onto the existing upsert + `touch_parent`
- [ ] Projector tests: `DetailUpdated` overwrites `subject`/`text` in place; `DetailRemoved` deletes the row

## 3. API edge
- [ ] `UpdateCostumeDetailRequest { detail, version }`
- [ ] `update_costume_detail` handler — `PATCH /v1/costumes/{id}/details/{detail_id}` with `// AUTHZ-GATE:` + `authorize_costume_scoped`
- [ ] `remove_costume_detail` handler — `DELETE /v1/costumes/{id}/details/{detail_id}` (`VersionRequest`), same gate
- [ ] Route registration in `handlers/mod.rs` + `lib.rs`
- [ ] Fluent: `problem-costume-detail-not-found` in `locales/de/errors.ftl` and `locales/en/errors.ftl`
- [ ] API handler tests: 200 / 404 (unknown costume) / 404 (unknown detail) / 409 (version fence) / 403 (authz)

## 4. Client data layer (no UI — #545)
- [ ] `CostumeRepository.removeDetail` / `.updateDetail` (`Result`, no `throw`)
- [ ] `CostumesController.removeDetail` / `.updateDetail`: pre-call `// AUTHZ-GATE:` capability check, `_resolveVersion` fence, 2xx ack → overlay version, bounded retry
- [ ] `costumeCommandErrorCopy`: `costume-detail.not-found` key, keyed on `code`
- [ ] Unit tests, Ok **and** Err branch for each `Result`; overlay unit test in the `addDetail submits a UUIDv7 wire id` style

## 5. Contract + verification
- [ ] `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`
- [ ] `bash scripts/regen-client.sh` → `vendor/breakdown_api/` byte-identical
- [ ] `cargo clippy --workspace --all-targets`, `cargo test -p core -p api`, architecture tests
- [ ] ast-grep guardrails clean (cqrs-boundary, problem-code-registry, no-panic, discard-result)
