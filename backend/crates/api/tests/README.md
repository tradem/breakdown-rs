<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# api integration tests — harness layout (issue #631)

These tests used to be **33 separate integration-test crates**, each statically
linking the full `api + infra + core + typst + opendal + reqwest + sqlx + …`
graph (a ~1 GB link each, 26–40 min per link on a 12-core machine). They are now
grouped into a handful of harnesses so the graph links a few times, not 33.

## How it works

- `crates/api/Cargo.toml` sets `autotests = false` and declares one `[[test]]`
  per harness. Cargo therefore discovers **only** the harness files.
- A harness (`auth.rs`, `handlers.rs`, `handlers_ai.rs`, `contract.rs`,
  `fault_injection.rs`) `#[path]`-includes its case files as modules.
- The case files themselves are ordinary `.rs` files in this directory; they are
  **not** test targets. Their `#[tokio::test]` functions still run — as part of
  the harness crate.
- Case files that use the shared helpers import them with `use crate::common;`;
  the harness root declares `mod common;`. `fault_injection_test.rs` is
  feature-gated and declares its own gated `mod common;`.

## Adding or moving a test

1. Put the case file in this directory (`crates/api/tests/`).
2. Add `#[path = "my_case.rs"] mod my_case;` to the matching harness file.
3. If it needs `common`, add `use crate::common;` (do not add a second
   `mod common;` unless the file is feature-gated).
4. Run the harness: `cargo test -p api --test handlers`.

Do not create a new top-level `tests/*.rs` target — that reintroduces the
per-file link cost. If a case file genuinely needs its own dependency set, add a
new `[[test]]` entry in `Cargo.toml` instead of relying on auto-discovery.

## Why the grouping is what it is

Grouping is by rough area, not by individual feature, to keep each harness
focused while still collapsing the link count. See
`../../.github/instructions/build-performance.instructions.md` for the full
rationale and the dev-machine cleanup recipe.
