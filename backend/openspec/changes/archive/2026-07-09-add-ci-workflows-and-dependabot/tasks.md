## 1. CI Pipeline (`.github/workflows/ci.yml`)

- [x] 1.1 Create `ci.yml` workflow file with triggers on `push` to `main` and `pull_request`
- [x] 1.2 Add `build` job: `cargo build --all-targets --all-features` with `dtolnay/rust-toolchain@stable` and `Swatinem/rust-cache@v2`
- [x] 1.3 Add `test` job: `cargo test --workspace` with toolchain and cache
- [x] 1.4 Add `clippy` job: `cargo clippy --all-targets --all-features -- -D warnings` with toolchain (including `clippy` component) and cache
- [x] 1.5 Add `fmt` job: `cargo fmt --all -- --check` with toolchain (including `rustfmt` component) and cache
- [x] 1.6 Add `check` job: `cargo check --all-targets --all-features` with toolchain and cache
- [x] 1.7 Add `deny` job: install `cargo-deny` and run `cargo deny check bans` with cache
- [x] 1.8 Set `CARGO_TERM_COLOR: always` as env variable across all jobs
- [x] 1.9 Set `working-directory: backend` as default for all jobs

## 2. Dependabot (`.github/dependabot.yml`)

- [x] 2.1 Create `.github/dependabot.yml` with `version: 2`
- [x] 2.2 Add `cargo` package ecosystem entry for `/backend` directory with weekly schedule
- [x] 2.3 Add `github-actions` package ecosystem entry for `/` directory with weekly schedule
- [x] 2.4 Configure PR limit (10), labels (`dependencies` for cargo, `ci`+`dependencies` for actions), and conventional commit prefixes (`chore(deps):` / `chore(ci):`)

## 3. Security Audit (`.github/workflows/audit.yml`)

- [x] 3.1 Create `audit.yml` workflow file with triggers on `schedule` (daily), `pull_request` (paths: `backend/Cargo.lock`), and `workflow_dispatch`
- [x] 3.2 Add audit job using `actions/checkout@v4` and `rustsec/audit-check@v2`
- [x] 3.3 Set `working-directory: backend` as default

## 4. Mutation Testing (`.github/workflows/mutation-testing.yml`)

- [x] 4.1 Create `mutation-testing.yml` workflow file with triggers on `schedule` (weekly, Sunday) and `workflow_dispatch`
- [x] 4.2 Add mutation testing job: install `cargo-mutants` via `cargo install cargo-mutants` and run `cargo mutants`
- [x] 4.3 Add `dtolnay/rust-toolchain@stable` and `Swatinem/rust-cache@v2` steps
- [x] 4.4 Set `working-directory: backend` as default
