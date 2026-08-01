// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

# Issue #148 — Mechanical guardrails: CQRS-boundary lint, test-shim-leak lint, handoff checklist

> Systematic implementation plan for adding the three mechanically enforced
> guardrails specified in issue #148, following the
> `no-string-interpolation-sql` precedent (precise, non-negotiable, CI-enforced
> grep gate in `.github/workflows/architecture-checks.yml`).

## 1. Problem statement

The retrospective on `feat/add-cross-cutting-audit-history` revealed three
systemic guardrail gaps that let anti-patterns slip through review and CI:

1. **CQRS boundary** — write-side code (command adapters, sagas, aggregates)
   queried read-model projections (`*Repository::find_by_id`) to resolve
   `series_id` for `EventMetadata`. This creates hidden coupling to projector
   presence and projection lag.
2. **Test-shim leak** — `aggressive_test_flush` (a test-only helper) was wired
   into every projector spawn in `main.rs` (production boot).
3. **Handoff-prompt review** — a handoff spec explicitly instructed the CQRS
   anti-pattern; it was never architecturally reviewed before dispatch.

The substantive fixes shipped on the audit-history branch (commits `0f1fb90`,
`1ebb97a`, `6a6be02`, `96fbd47`) and issue #147 (#150) cleaned the command
adapters. This issue adds the **mechanical gates** so the patterns cannot
recur.

## 2. Current-state audit (branch cut from `main`)

| Gate | Scoped path | Current violations on `main` |
|---|---|---|
| Gap 1 | `crates/infra/src/event_store/` | **0** (cleaned by #150) |
| Gap 1 | `crates/infra/src/sagas/` | **0** (cleaned by `0f1fb90`) |
| Gap 1 | `crates/infra/src/photo/sagas/` | **23** `find_by_id` across 3 files (all in `resolve_series_id` except 1 version-fetch per deletion saga) |
| Gap 2 | `crates/api/src/` (production files) | **0** (`main.rs` already uses `ProjectorFlushConfig::default()` everywhere) |

Remaining Gap-1 offenders on `main`:

| File | `find_by_id` count | Purpose |
|---|---|---|
| `photo/sagas/thumbnail.rs` | 7 | `resolve_series_id` (audit metadata) — replaceable |
| `photo/sagas/deletion.rs` | 8 | 7 × `resolve_series_id` + 1 × version fetch (concurrency guard) |
| `photo/sagas/continuity_deletion.rs` | 8 | 7 × `resolve_series_id` + 1 × version fetch (concurrency guard) |

## 3. Design decision (recorded)

**User decision (2026):** implement Gap 1 with an **allowlist sentinel** for the two
remaining legitimate version fetches, instead of a strict blanket ban or excluding
`photo/sagas/` from scope.

Rationale: the version fetch in the deletion sagas is **not** audit-metadata
resolution — it reads the photo's current aggregate version to build the
`ExpectedVersion::Exact(stream_version)` optimistic-concurrency guard for
`DeletePhoto` (and `DeletePhoto.version` for the aggregate's `check_version`).
Eliminating it would require relaxing the concurrency guard — a behavioral
change in deletion semantics that is out of scope for a guardrails issue.

**Migrated to AST-based linting (ast-grep 0.45):** the sentinel is the native
ast-grep suppression `// ast-grep-ignore: cqrs-boundary` on the call line (with
a justification comment above), and the gate itself is a structural rule
(`backend/rules/cqrs-boundary.yml`) instead of a text grep. This is strictly
more precise than the grep variant: it matches method-call AST nodes (so
rustfmt line-splitting and field names like bare `repo` cannot evade it), it
ignores comments/strings, and the suppression is same-line + reviewable.

## 4. Gap 1 — CQRS-boundary lint

### 4.1 Saga migration (write-side must use event-data context)

The three photo sagas receive `Event<_, EventMetadata>` in their handlers.
`EventMetadata.series_id` is populated at the API edge / by upstream commands
and travels with the event — exactly the pattern AGENTS.md §1 prescribes
("context must come from the event data itself"). Extract it as:

```rust
let series_id = event.metadata.data.as_ref().and_then(|m| m.series_id);
```

This is best-effort: events appended without metadata (e.g. raw `eappend` in
integration tests) yield `None`, mirroring the old tolerant `Ok(None)` path.

**`thumbnail.rs`** (`PhotoThumbnailSaga`):
- Delete `resolve_series_id` and all 7 repo fields/args (`photo_repo`,
  `costume_repo`, `character_repo`, `season_repo`, `scene_shoot_repo`,
  `scene_repo`, `episode_repo`).
- `handle` extracts `series_id` from `event.metadata.data` and passes it into
  `process_upload(id, series_id)`; the `NormalizeOriginal` / `GenerateVariant`
  commands and `EventMetadata` use it directly.

**`deletion.rs`** (`PhotoDeletionSaga`):
- Delete `resolve_series_id` and the 6 parent-chain repo fields/args
  (`costume_repo`, `character_repo`, `season_repo`, `scene_shoot_repo`,
  `scene_repo`, `episode_repo`). Keep `repo` (`PhotoRepositoryImpl`).
- `PhotoUnlinked` handler: `series_id` from `event.metadata.data`; the
  `self.repo.find_by_id(photo_id)` version fetch stays, annotated with
  `// CQRS-OK:` (justification comment).

**`continuity_deletion.rs`** (`ContinuityDeletionSaga`):
- Same as `deletion.rs`. Keep `repo` for the version fetch and `count_links`
  (costume-side refcount check, documented in AGENTS.md; not a `find_by_id`
  call).

**Call-site updates** (constructor signatures shrink):
- `crates/api/src/main.rs` — 3 spawn calls drop 6 repo args each.
- `crates/integration-tests/tests/photo_round_trip.rs` (thumbnail),
  `photo_nm_deletion.rs` (thumbnail + deletion),
  `continuity_photo_round_trip.rs` (continuity) — same arg removal.

### 4.2 CI job (`cqrs-boundary`)

Add to `.github/workflows/architecture-checks.yml`, modeled on the
`no-string-interpolation-sql` job:

- AST-based rule file `backend/rules/cqrs-boundary.yml` (`id: cqrs-boundary`,
  `severity: error`, `language: Rust`): matches any `$REPO.find_by_id($$$)` or
  `$REPO::find_by_id($$$)` **call expression**.
- Job scans the write-side dirs only:
  `crates/infra/src/event_store/`, `crates/infra/src/sagas/`,
  `crates/infra/src/photo/sagas/` (the API layer is never scanned by this
  rule, so handler reads stay unflagged).
- Suppression: `// ast-grep-ignore: cqrs-boundary` on the call line for the
  two non-audit version guards; any other match fails the job (`severity:
  error` → non-zero exit).
- ast-grep 0.45.0 is installed in the job from a SHA256-pinned release zip
  (no third-party action).

## 5. Gap 2 — Test-shim-leak lint

Add `test-shim-leak` job to `.github/workflows/architecture-checks.yml`:

- AST-based rule file `backend/rules/test-shim-leak.yml` (`id: test-shim-leak`,
  `severity: error`, `language: Rust`):
  - `known_test_helpers` utility — denies `test_profile(...)`,
    `$SELF.test_profile(...)`, `$TYPE::test_profile(...)` and the historical
    `aggressive_test_flush` variants (extend for any new test-only helper).
  - `with_config_without_default` utility — denies
    `spawn_$NAME_with_config($$$)` calls whose args do **not** contain
    `ProjectorFlushConfig::default()`.
- Job scans **production** files under `crates/api/src/` — `main.rs` plus all `.rs`
  files, **excluding** test modules: `*_tests.rs`, `*_test.rs`,
  `test_helpers.rs`, and anything under a `tests/` directory.

Currently zero violations; the gate keeps it that way.

## 6. Gap 3 — Handoff-prompt architecture checklist (AGENTS.md §3)

Add a subsection to AGENTS.md §3 (Workflow & Best Practices):

- Does the plan have the write-side query a read-model projection? (CQRS
  violation — reject unless at the API edge.)
- Does the plan introduce `unwrap`/`expect`/`panic` in hot paths (adapters,
  sagas, projectors, handlers)?
- Does the plan call test-only helpers from production spawn paths?
- Does the plan carry audit metadata (`series_id`) in a way that couples to
  projector presence?

## 7. Verification plan

1. Run both new lint greps locally against the tree → expect **green**.
2. `cargo check --workspace --all-targets --exclude breakdown-fuzz-targets`
   (compiles the sagas, `main.rs`, and integration-test call sites).
3. `cargo clippy --workspace --all-targets --all-features
   --exclude breakdown-fuzz-targets -- -D warnings`.
4. `cargo fmt --all -- --check`.
5. `cargo test -p architecture_tests` (boundary rules still hold).
6. If Docker is available locally: run the photo integration tests that
   exercise the migrated sagas (`photo_round_trip`, `photo_nm_deletion`,
   `continuity_photo_round_trip`) with `TESTCONTAINERS_REUSE=1` if possible.
   Otherwise rely on the `integration-tests` CI job.

## 8. Task checklist

- [x] Plan doc committed (this file).
- [x] Gap 1: migrate `thumbnail.rs` to `event.metadata.series_id`.
- [x] Gap 1: migrate `deletion.rs` (series_id from metadata; version fetch
      marked `// CQRS-OK:`).
- [x] Gap 1: migrate `continuity_deletion.rs` (same).
- [x] Gap 1: update `spawn_*` signatures + `main.rs` + integration tests.
- [x] Gap 1: add `cqrs-boundary` job to `architecture-checks.yml`.
- [x] Gap 2: add `test-shim-leak` job to `architecture-checks.yml`.
- [x] Gap 3: add handoff checklist to AGENTS.md §3.
- [x] Verify: lint greps, check, clippy, fmt, architecture tests.
- [x] Optional: photo integration tests locally (Docker) — all three green
      (`photo_round_trip`, `photo_nm_deletion`, `continuity_photo_round_trip`).

## 9. Implementation notes (post-hoc)

- The gates are AST-based ast-grep 0.45 rules (`backend/rules/*.yml`), not
  text greps. ast-grep matches method-call AST nodes, so rustfmt line-splitting
  (`.repo` / `.find_by_id` on separate lines) and bare `repo` field names
  cannot evade it, and comments/strings are never matched. The initial grep
  prototype was kept line-based like `no-string-interpolation-sql`; the
  ast-grep migration removes the two holes that grep had (multi-line chains,
  non-underscore `repo` field).
- Suppression uses ast-grep's native `// ast-grep-ignore: cqrs-boundary`
  comment on the call line (justification comment above) — the literal string
  `ast-grep-ignore` must not appear in ordinary comments, or ast-grep reports
  `unused-suppression`.
- Each CI job runs only its own rule via `ast-grep scan -r rules/<rule>.yml
  <paths>`: the `cqrs-boundary` rule is scoped to the write-side dirs (the API
  layer legitimately uses `find_by_id`), and `test-shim-leak` is scoped to
  production api files.
- ast-grep 0.45.0 is installed in CI from a SHA256-pinned release zip (no
  third-party action; matches the repo's SHA-pinning hardening rules).
- The `backend/git-hooks/pre-commit` hook runs both rules on **staged** files
  (same path scoping as the CI jobs): `cqrs-boundary` for staged write-side
  files, `test-shim-leak` for staged production api files. If ast-grep is not
  installed locally it warns and skips — CI remains the authoritative gate.
- Rule bug fixed during hook review: metavariables cannot appear *inside*
  identifiers, so `spawn_$NAME_with_config($$$)` never matched. The rule now
  identifies `spawn_*_with_config` calls via `regex: '^spawn_[a-z0-9_]*_with_config\s*\('`
  on the call node and excludes `ProjectorFlushConfig::default()` with
  `has: { stopBy: end }` (the default argument is a descendant of the call,
  not a direct child).
- The `audit_cross_cutting_tests` pool-timeout flake observed during
  verification is pre-existing and tracked in issue #149 (not caused by this
  change); the three photo integration tests that exercise the migrated
  sagas all pass.
