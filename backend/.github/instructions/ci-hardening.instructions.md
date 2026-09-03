---
description: CI guardrails - ast-grep rule set, guardrail jobs and rule editing guidance.
applyTo:
  - "rules/**"
  - "rules-tests/**"
  - "scripts/**"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Mechanical Guardrails (CI) — detail


- **Mechanical Guardrails (CI):** The `architecture-checks.yml` workflow enforces the
  write-side CQRS boundary (`cqrs-boundary` job: no `find_by_id` in
  `crates/infra/src/event_store/` + `**/sagas/`, via the AST-based ast-grep rule
  `backend/rules/cqrs-boundary.yml`; `// ast-grep-ignore: cqrs-boundary` for non-audit
  reads) and blocks test-only helpers in production api code (`test-shim-leak` job:
  `test_profile`/`aggressive_*`/`spawn_*_with_config` without
  `ProjectorFlushConfig::default()`, via `backend/rules/test-shim-leak.yml`) — issue #148.
  The `error-hygiene` job additionally enforces, on all production `crates/*/src` files
  (test modules excluded), that no fallible result is discarded with `let _ = <call>`
  (`backend/rules/discard-result.yml`) and that `*_for_test` helpers are gated behind
  `#[cfg(feature = "test-support")]` (`backend/rules/test-helper-gate.yml`) — issue #165
  review lessons. All rules accept an explicit `// ast-grep-ignore: <rule-id>` suppression
  with a justification comment — except `problem-code-registry`, which is
  deliberately non-suppressible: the shared checker rejects any
  `ast-grep-ignore: problem-code-registry` directive, because a suppressed
  standalone declaration would compile unregistered (issue #232). The
  `problem-code-registry` job (issue #232) runs the
  shared, syntax-aware scanner `backend/scripts/check-problem-code-registry.sh`
  (rule `backend/rules/problem-code-registry.yml`, rule tests in
  `backend/rules-tests/`): every `pub const …: ProblemCode` must be declared
  through the `problem_codes!` macro in `error_registry.rs` — a standalone
  declaration compiles but is never registered. The `backend/git-hooks/pre-commit`
  hook mirrors these guardrails on staged files (warning only if ast-grep is not
  installed; CI remains the authoritative gate).
  The `rust-security-ast-grep` job (Layer 9, issue #262) enforces two Rust
  security rules on all production `crates/*/src` files: no reqwest TLS bypass
  (`danger_accept_invalid_certs/hostnames(...)` with anything but the literal
  `false` — consts/variables/expressions are rejected fail-closed; CWE-295;
  ADR-024 mandates rustls + pinned root CAs) via
  `backend/rules/reqwest-no-dangerous-tls.yml`, and no hardcoded HTTP auth
  credentials (`.basic_auth`/`.bearer_auth` with an inline ordinary or raw
  string literal — CWE-798, complements the gitleaks text scan structurally)
  via `backend/rules/reqwest-no-hardcoded-auth.yml`. Both are vendored from
  [`coderabbitai/ast-grep-essentials`](https://github.com/coderabbitai/ast-grep-essentials)
  (upstream ids `reqwest-accept-invalid-rust` and
  `secrets-reqwest-hardcoded-auth-rust`, generalized to receiver-agnostic
  matching and re-severity'd to `error`) with provenance documented in the rule
  headers. Of the collection's 8 Rust security rules the remaining six are
  deliberately **not** vendored and should not be re-proposed without cause:
  the sqlx-builder pair (`empty-password-rust`, `hardcoded-password-rust`) does
  not even parse under ast-grep 0.45.0 (reserved characters in utility ids) and
  targets the `*ConnectOptions` builder API we do not use (`DATABASE_URL` via
  `PgPoolOptions` only); the `postgres`/`tokio-postgres` password rules target
  crates absent from the stack; and `ssl-verify-none-rust` targets `openssl`,
  which we never link (rustls exclusively). Revisit individually if one of these
  dependencies is ever introduced.
