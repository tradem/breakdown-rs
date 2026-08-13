// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Architecture Constraints

== Technical Constraints

#table(
  columns: 3,
  table.header([Area], [Constraint], [Rationale]),
  [Language], [Rust (stable toolchain)], [memory safety without GC; fits event-sourcing load profile],
  [Workspace layout], [Hexagonal crates: `core`, `infra`, `api`, `architecture`, `integration-tests`, `me100-fuzz`], [source-level boundary enforcement (#adr-ref(num: "017", slug: "architecture-testing-strategy", title: "Architecture-Testing Strategy"))],
  [Write-side persistence], [SierraDB via RESP3], [append-only event streams (#adr-ref(num: "015", slug: "sierradb-event-store-postgres-projections", title: "SierraDB EventStore Split"), #adr-ref(num: "016", slug: "sierradb-runtime-and-round-trip", title: "SierraDB Round-Trip"))],
  [Read-side persistence], [PostgreSQL projections], [rich SQL queries, report generation],
  [Event-sourcing library], [`kameo_es` + custom adapters], [aggregates as actors; command/reply pattern],
  [Object storage], [Garage (S3) via OpenDAL], [self-hosted, no vendor lock-in (#adr-ref(num: "009", slug: "photo-storage-opendal-s3-api", title: "S3 Photo Storage"))],
  [Documentation], [arc42 in Typst], [single binary, version-controlled (#adr-ref(num: "008", slug: "documentation-tooling-and-structure", title: "Documentation Tooling"))],
  [Release versioning], [Git tag `api-vX.Y.Z`], [reproducible release images (#adr-ref(num: "020", slug: "rust-component-versioning", title: "Rust Component Versioning & Release Mechanics"))],
)

== Organizational Constraints

#table(
  columns: 2,
  table.header([Constraint], [Description]),
  [Test-driven development], [deterministic unit tests in `core`; integration tests with `testcontainers` (Tiers 1–4)],
  [No panics in production code], [`unwrap()` / `expect()` / `panic!()` are lint-level errors in adapters, sagas, projectors, handlers],
  [No string-interpolated SQL], [all `sqlx::query*` calls use static queries + `.bind()`; `ORDER BY` columns from a hardcoded allowlist],
  [Mechanical guardrails], [`rust_arkitect`, ast-grep rules, compile-time assertions (e.g. `#232` registry)],
  [Release process], [every release must be reproducible from git tag; changelogs dated in release branch],
)

== Code Conventions

- SPDX license headers (`AGPL-3.0`) and co-author attribution on every source file.
- Branches follow `docs/`, `feature/`, `fix/`, `chore/` prefixes.
- Commits use conventional-commit format.
- `cargo fmt`, `cargo clippy` (deny warnings), `cargo deny check bans` are CI-enforced.

// TODO: add deployment-window / maintenance-window constraints if agreed with ops
