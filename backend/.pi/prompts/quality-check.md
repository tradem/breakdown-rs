---
description: Run cargo mutants and integration-tests, report results and surviving mutants (Experimental)
---

Run mutation testing and integration tests for the breakdown-rs workspace.

**Input**: Optionally specify a crate or scope (e.g., `/quality-check infra`). If omitted, run on the workspace root.
**Provided arguments**: $@

**Steps**

1. **Select the scope**

   - If a crate name is provided, use it (e.g., `infra`, `core`, `api`)
   - If workspace-scoped (e.g., `--all`), target the entire workspace
   - If ambiguous, ask the user

   Always announce: "Checking <scope>."

2. **Run cargo mutants**

   Mutate the chosen scope and report surviving mutants:

   ```bash
   cargo mutants -p <crate> --timeout 60s -- --quiet 2>&1
   ```

   - For workspace scope: `cargo mutants --workspace --timeout 60s -- --quiet`
   - For a single changed crate: `cargo mutants -p <crate> --timeout 60s -- --quiet`
   - For surface-only (fast path, no generated code): `cargo mutants -p <crate> --include-surface --timeout 60s -- --quiet`

   **Budget-aware mode for slow crates (e.g., `infra` with supervisor):**
   The `infra` crate contains a budget-exhaustion test that runs ~150s per mutant.
   When running mutants on `infra`, use `--skip tests` to skip slow/integration tests
   and only surface-mutate the library code:

   ```bash
   cargo mutants -p infra --include-surface -m "src/lib.rs" --timeout 60s -- --quiet
   ```

   **Parse results:**
   - `*** result: Fixed(N)` → All N mutants killed (no surviving mutants ✅)
   - `*** result: Passing` → No mutants were generated (empty surface ✅)
   - `*** result: Failure(T)` → At least one mutant survived (⚠️ fix the code or add a test)
   - `*** result: Ignored(M/A)` → M mutants ignored, A skipped

   **Surviving mutants:**

   On failure, identify each `---- <crate>::<module>::<function>` entry and its mutation:
   - Read the affected file and the mutation body
   - Determine if the existing tests cover the mutated path
   - If a new test is needed, write a unit test that asserts the mutated behavior
   - If the mutation should survive (safe branch), add a `#[allow(dead_code)]` comment or
     explain in the task why it is intentionally reachable
   - Re-run until all mutants are killed or all survivors are justified

   **Report:**
   Print a summary table:

   ```
   mutation  | crate    | function       | status  | survived_by
   ----------+----------+----------------+---------+-------------------
   negated   | infra    | compute_backoff| killed  |
   branch    | infra    | is_capped      | killed  |
   arm       | core::   | validate       | survived| (no test)
   ```

   Then state:
   - ✅ "N/N mutants killed" or
   - ⚠️ "N/M mutants survived — see table above"

3. **Run integration tests**

   If Docker is available, run the Tier-1–3 integration tests:

   ```bash
   docker info >/dev/null 2>&1
   ```

   **If Docker is available:**

   ```bash
   cargo test -p integration-tests 2>&1
   ```

   Report the test result table. Any failure should be copied verbatim into the task update.

   **If Docker is NOT available:**

   - Note: "Docker not available — skipping integration-tests (will be verified on CI)"
   - Do NOT continue past this step. Explain that Tier-1-3 tests require a container
     runtime and that the CI workflow (`.github/workflows/integration-tests.yml`) will
     exercise them on `ubuntu-latest`.

4. **Update tasks if needed**

   After a successful run (all mutants killed, all integration tests passed):
   - Mark task 3.5 as complete in `openspec/changes/<change>/tasks.md`
   - Mark task 4.4 as complete (if Docker was available and tests passed)
   - Run `openspec verify --no-interact` to update the change status

   On failure (surviving mutants):
   - List surviving mutants and their impact
   - Recommend which test to add or which source branch to harden
   - STOP — do not mark tasks complete until all mutants are killed

5. **Lint and format check (optional, on CI-friendly runs)**

   In a CI context (or when the user asks for a full gate), also run:

   ```bash
   cargo fmt --all --check
   cargo clippy --workspace --all-targets -- -D warnings
   ```

   Report pass/fail and fix any warnings before re-marking tasks.

**Guardrails**

- Never accept surviving mutants silently. Every survivor must either be tested
  (new unit test or assertion) or explicitly justified with a comment.
- If `cargo mutants` generates code that the workspace does not compile, run the
  failing mutant in isolation first: `cargo mutants -p <crate> --include-surface
  --include generated` to verify. If the generated code itself has issues, file
  a follow-up task for dependency/tooling upgrades.
- Integration tests are black-box. Do NOT mock network or containers — only use
  the existing `testcontainers` harness in `crates/integration-tests`.
- Budget-aware mode is mandatory for the `infra` crate to keep local CI fast.
