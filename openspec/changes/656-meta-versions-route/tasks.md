<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 656 — Tasks

## 1. Backend meta route

- [ ] 1.1 `crates/core/src/lib.rs` + `crates/infra/src/lib.rs`: expose
      `pub const VERSION: &str = env!("CARGO_PKG_VERSION")`.
- [ ] 1.2 `crates/api/src/meta.rs`: `MetaVersionsResponse` DTO
      (utoipa `ToSchema`) + `get_meta_versions` handler (200 JSON,
      compile-time constants only).
- [ ] 1.3 Route registration in `handlers::routes()`
      (`/meta/versions` → GET) and `requirement_for`: `/meta` →
      `Requirement::Authenticated` (fall-through is `BlockMember` — must be
      explicit).
- [ ] 1.4 ApiDoc: path + schema entries; regenerate `backend/openapi.yaml`
      (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`).
- [ ] 1.5 Tests: unit test for the handler shape; authz-middleware test for
      `/meta/versions` (no token → 401; dev token → 200).

## 2. Client

- [ ] 2.1 `bash frontend-flutter/scripts/regen-client.sh`; commit the
      generated diff (contract surface only).
- [ ] 2.2 `app_info` feature: repository method returning `Result`
      (no `throw`), `@riverpod` controller, About screen renders backend
      crate versions with graceful `AsyncValue` loading/error state.
- [ ] 2.3 l10n de/en ARB parity for new copy; widget tests for Ok/Err
      branches of the repository/controller.

## 3. Validation

- [ ] 3.1 `cargo test -p api -p core -p infra`, `cargo clippy`, drift CI
      green locally (`UPDATE_OPENAPI=1` diff empty afterwards).
- [ ] 3.2 `flutter analyze` + feature tests green.
