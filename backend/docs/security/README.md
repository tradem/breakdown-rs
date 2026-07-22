// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

# Security Guidelines

## SQL Injection Prevention

### Hard rule

Every SQL statement passed to `sqlx::query(...)`, `sqlx::query_as(...)`, or
`sqlx::query_scalar(...)` **must** be a static `&str` literal (or `r#"..."#`).
All dynamic values go through `.bind()`. Identifiers (column/table names,
`ORDER BY` column) must come from a hardcoded allowlist, **never** from request
input — Postgres cannot bind identifiers.

```rust
// ✅ Safe — static literal with $1 placeholder + .bind()
sqlx::query(r#"SELECT * FROM projection_costume WHERE id = $1"#)
    .bind(costume_id)
    .fetch_optional(&self.pool)
    .await

// ⛔ Injectable — string interpolation in SQL text
sqlx::query(&format!("SELECT * FROM projection_costume WHERE id = '{id}'"))

// ⛔ Injectable — string concatenation in SQL text
sqlx::query("SELECT * FROM projection_costume WHERE id = '" + id + "'")
```

The CI job `no-string-interpolation-sql` in `.github/workflows/architecture-checks.yml`
enforces this mechanically with a `grep` guard that blocks `format!` and `+`
inside `sqlx::query(...)` / `query_as(...)` / `query_scalar(...)` calls.

### Safe patterns for dynamic filters

When `list_*` endpoints gain free-text search, dynamic sort, or pagination:

| Feature | Safe pattern |
|---|---|
| **`ILIKE` search** | `escape_like_pattern(&input)` helper masks `%`, `_`, `\\`; pass `format!("%{}%", escaped)` **as a bound parameter**, not as SQL text. |
| **Sort columns** | Hardcoded `match` over an allowlist; never bind an identifier. |
| **Pagination** | Hard `LIMIT <= 100` clamp; always use `$1` / `.bind()`. |
| **Full-text search** | Postgres `to_tsquery($1)` (typed parameter). |
| **Dynamic `IN (...)` lists** | Use `sqlx::query(...).bind(slice)` with `= ANY($1)` and a Rust array/slice, or build the `$1, $2, ...` placeholders at query time **with a hardcoded upper bound** (e.g., max 100 items). |

### Review checklist for SQL changes

- [ ] Is the SQL string a static `&str` / `r#"..."#` literal? (No `format!`, no `+`)
- [ ] Are all dynamic values passed via `.bind()`?
- [ ] Are identifiers (column/table names) from a hardcoded allowlist, not user input?
- [ ] If `ILIKE` is used: is the input escaped via `escape_like_pattern`?
- [ ] If pagination: is there a `LIMIT` cap?
- [ ] If `IN (...)` is dynamically sized: is there an upper bound?

## DB Safety Posture

### Migration reversibility

Every database migration **must** have a matching `.down.sql` that cleanly
reverses the changes made by its `.up.sql`. This ensures production rollbacks
are safe and deterministic.

The CI test `migrations_are_reversible` in `crates/integration-tests`
enforces this:

1. Applies all migrations up (via the compile-time embedded migrator).
2. Undoes them one-by-one in reverse version order, calling `undo(&pool, target)`
   for each step down to version 0.
3. Asserts the `public` schema contains no tables other than the internal
   `_sqlx_migrations` table.
4. Re-applies all migrations up to confirm idempotency.

The test runs as a Tier-1 (Postgres-only) integration test via `testcontainers`
on every PR that touches migrations, with no additional container dependency.

### Non-reversible migrations

If a migration is intentionally non-reversible (e.g. a data backfill,
destructive column conversion), it must be explicitly opted out:

1. Add `-- no-undo` at the top of the `.down.sql` file.
2. Register the version and a documented reason in the
   `NON_REVERSIBLE_MIGRATIONS` allowlist inside the test file.

The test will:
- **Skip** the undo step for that version.
- **Fail loudly** if a `-- no-undo` marker exists without a matching
  allowlist entry.
- **Fail loudly** if an allowlist entry references a non-existent migration
  (stale entry).

This policy prevents silent additions of irreversible schema changes and
ensures every opt-out is intentional and documented.
