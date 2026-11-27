// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#import "template.typ": *


= Architecture Constraints

== Technical Constraints

#table(
  columns: 3,
  table.header([Area], [Constraint], [Rationale and Reference]),
  [Backend language], [Rust 1.100, edition 2024 (`unsafe_code = "deny"`)], [Memory safety without garbage collection (#adr-ref(num: "020", slug: "rust-component-versioning", title: "Rust Component Versioning"))],
  [Backend crates], [`core`, `infra`, `api`, `architecture`, `integration-tests`, `test_support`, `fuzz-targets`], [Compile-time and AST boundary checks (#adr-ref(num: "001", slug: "hexagonal-architecture", title: "Hexagonal Architecture"), #adr-ref(num: "017", slug: "architecture-testing-strategy", title: "Architecture Testing"))],
  [Write persistence], [SierraDB 0.3.1 over RESP3 + vendored `kameo_es` 0.2], [Append-only event streams and reservation claims (#adr-ref(num: "015", slug: "sierradb-event-store-postgres-projections", title: "SierraDB + PG Split"), #adr-ref(num: "036", slug: "es-native-reservation-streams-cross-aggregate-uniqueness", title: "Reservation Streams"))],
  [Read persistence], [PostgreSQL 16 with `sqlx` 0.9], [Flat SQL projections, `ai_import` queue, and `LISTEN/NOTIFY` hub (#adr-ref(num: "015", slug: "sierradb-event-store-postgres-projections", title: "SierraDB + PG Split"))],
  [Time library], [`jiff` 1.0 + `infra::db_time` (`chrono` banned)], [Fixes `RUSTSEC-2026-0543` and keeps RFC 3339 event bytes identical (#adr-ref(num: "040", slug: "jiff-replaces-chrono", title: "jiff Replaces chrono"))],
  [Object storage], [Garage v1.0.1 (S3 API) through OpenDAL], [Self-hosted storage for photos, AI blobs, and S3 report backups (#adr-ref(num: "009", slug: "photo-storage-opendal-s3-api", title: "OpenDAL S3 Storage"))],
  [Secrets store], [HashiCorp Vault OSS 1.20 (Transit + KV-v2)], [Envelope encryption and crypto-shredding for external credentials (#adr-ref(num: "027", slug: "secrets-vault-for-external-credentials", title: "Secrets Vault"))],
  [Client stack], [Flutter / Dart (Android first), Riverpod codegen, Drift SQLite, `fpdart`], [Typed offline read cache and explicit `Result` error values (#adr-ref(num: "033", slug: "flutter-client-versioning", title: "Flutter Versioning"), #adr-ref(num: "034", slug: "flutter-app-localization-gen-l10n", title: "Flutter Localization"))],
  [Wire contract], [Code-first `backend/openapi.yaml` (`utoipa` 6 → `breakdown_api`)], [Single contract checked for drift on both backend and client (#adr-ref(num: "006", slug: "utoipa-openapi-codegen", title: "utoipa OpenAPI"), #adr-ref(num: "021", slug: "api-versioning", title: "API Versioning"))],
  [Transport security], [Caddy HTTPS edge, `step-ca` internal store TLS, pinned client Root CA], [Public HTTPS at Caddy, TLS on API-to-store links, and pinned client CA (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Encryption in Transit"), #adr-ref(num: "025", slug: "https-edge-and-cert-rotation", title: "HTTPS Edge"), #adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning"))],
  [Documentation], [Typst 0.15.1 + PlantUML in ASD-STE100], [Single-binary PDF/HTML pipeline and clear English (#adr-ref(num: "008", slug: "documentation-tooling-and-structure", title: "Documentation Tooling"))],
)

== Organizational and Quality Constraints

#table(
  columns: 2,
  table.header([Constraint], [Rule]),
  [OpenSpec governance], [Feature changes track proposals, designs, and delta specs under `/openspec/`.],
  [Test-driven workflow], [Backend runs unit tests, `testcontainers` Tiers 1–4, nightly `cargo-fuzz`, and CI `cargo-mutants`. Flutter runs unit, widget, golden, Gherkin, and device tests with `coverde` coverage gates.],
  [No panics or throws], [Backend production paths reject `unwrap`, `expect`, `panic!`, `todo!`, and `unreachable!`. Flutter `data/` and `domain/` reject `throw` and return `Result`.],
  [No discarded results], [`ast-grep` (`discard-result`) in Rust and `breakdown_lints` in Dart reject ignored fallible calls.],
  [Static SQL only], [All `sqlx::query*` calls must use static string literals and `.bind()` parameters.],
  [CI hardening], [Every GitHub Action pins a 40-character commit SHA and passes untrusted values through `env:`.],
)

== Licensing and Repository Conventions

- All hand-written source, spec, workflow, and documentation files carry an
  `AGPL-3.0` SPDX header and one `Co-authored-by:` line per contributor by
  project convention.
- CI runs `./scripts/add-spdx-headers.sh --check` to verify `SPDX-License-Identifier`
  markers on supported source and doc extensions while skipping regenerated
  trees (`vendor/breakdown_api/`, `*.g.dart`). `Co-authored-by:` lines and
  `.puml` headers are reviewed conventions rather than automated script checks.
- `gitleaks` scans commits across Rust, Dart, YAML, and ARB files to prevent
  secret leaks.
- All entity and event identifiers use `UUIDv7` (`uuid::Uuid::now_v7()`).
