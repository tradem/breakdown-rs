<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

---
description: Dev/test build performance — profiles, faster linker, integration-test harness layout, artifact/container cleanup (issue #631).
applyTo:
  - "Cargo.toml"
  - ".cargo/**"
  - "scripts/cc-linker.sh"
  - "crates/api/Cargo.toml"
  - "crates/api/tests/**"
---

# Dev/test build performance (issue #631)

Local iteration is dominated by **compile/link time** and the **disk/metadata
footprint of `target/`**, not by test runtime. Observed on a 12-core / 15 GB
machine before the fix:

| Metric | Value |
|---|---|
| `api` test binary size | ~1 GB each |
| `crates/api/tests/*.rs` link targets | 33 |
| `target/debug/deps` logical size | ~1.3 TB |
| `target/debug/incremental` | tens of GB, 40k+ files |
| Single-binary link time | 26–40 min |

The fix has four independent parts. Keep them together — reducing debug info is
what makes the other three safe.

## 1. Dev/test profiles (workspace `Cargo.toml`)

```toml
[profile.dev]
debug = "line-tables-only"
split-debuginfo = "unpacked"

[profile.test]
debug = "line-tables-only"
split-debuginfo = "unpacked"
```

- `line-tables-only` keeps file/line info for readable backtraces but drops the
  bulky variable/type DWARF that made each executable ~1 GB.
- `split-debuginfo = "unpacked"` keeps the remaining DWARF in `.dwo`/`.dwp`
  sidecars instead of embedding it in every linked executable. It only affects
  Linux/macOS; it is accepted (and ignored) elsewhere.
- **Release profiles are untouched.** Do not re-enable full DWARF locally.

## 2. Faster linker (`scripts/cc-linker.sh`)

`.cargo/config.toml` sets the target linker to `scripts/cc-linker.sh`, which
keeps the C compiler as the link *driver* and asks it for a faster backend:

```
mold  →  lld  →  the system default linker
```

The fallback matters: a machine with neither mold nor lld builds exactly as
before. Install one for the fast path (`sudo apt install lld` / `dnf install
lld`; mold from its upstream repo). `rust-lld` alone is **not** usable here —
it cannot find `-lgcc_s` without extra driver flags — which is why the wrapper
delegates to `cc -fuse-ld=lld`. Override the driver with `CC=clang` if needed.

The path is resolved relative to the workspace root (the directory cargo runs
rustc in), so it works from any invocation CWD inside `backend/`.

## 3. Integration-test harnesses (`crates/api/tests/`)

Every `tests/*.rs` file used to be its own integration-test crate, so the whole
`api + infra + core + typst + opendal + reqwest + …` graph was statically linked
33 times. Tests are now grouped into a handful of harnesses declared explicitly
in `crates/api/Cargo.toml`:

```toml
autotests = false

[[test]]
name = "handlers"
path = "tests/handlers.rs"
# …
```

Each harness `#[path]`-includes its case files as modules, so the graph links
once per group:

| Harness | Case files |
|---|---|
| `auth` | `auth_authorization`, `auth_jwks`, `auth_mod`, `tls_config` |
| `handlers` | the general `handler_*` suites |
| `handlers_ai` | `handler_ai_import_*`, `handler_audit` |
| `contract` | `bundle_coverage`, `openapi_drift`, `problem_golden`, `route_coverage`, `http_error_surface` |
| `fault_injection` | `fault_injection_test` (feature-gated) |

**Adding a test:** create the case file under `crates/api/tests/` and add a
`#[path = "…"] mod …;` line to the matching harness in `tests/<harness>.rs`.
Do **not** add a new top-level `tests/*.rs` target. Case files share the
harness's `common` module via `use crate::common;` (the harness root declares
`mod common;`); a feature-gated case file may keep its own gated `mod common;`.
The `autotests = false` switch is what stops cargo from treating the case files
as targets — without it the consolidation is silently undone.

## 4. Parallelism (`.cargo/config.toml`)

`[build] jobs = 8` (was `3`) on a 12-core / 15 GB machine. The linker is the
memory peak, so 8 leaves headroom. This is only safe *after* the debug-info
reduction above.

## Dev-machine cleanup recipe

`cargo` never garbage-collects stale artifacts; every changed source/flags
combination leaves the previous binary behind. On btrfs the real failure is
**metadata exhaustion** — `ld` can die with `signal 7 [Bus error]` (or `mkdir`
fails with `ENOSPC`) while hundreds of GB of data space remain free.

Diagnose:

```bash
btrfs filesystem usage /            # watch Metadata,DUP — 8 GiB chunks, DUP
df -h /                             # data space may still look fine
du -sh backend/target               # apparent size (btrfs reports logical)
find backend/target -type f | wc -l # file count is the real trigger
```

Reclaim (safe — a rebuild follows the profile change anyway):

```bash
cd backend
./scripts/reclaim-disk.sh              # report only: target/, backups/, docker leftovers
./scripts/reclaim-disk.sh --apply      # cargo sweep: delete artifacts older than 30 days
./scripts/reclaim-disk.sh --apply -t 7 # ... older than a week (heavy iteration phase)
./scripts/reclaim-disk.sh --apply --maxsize 200GB   # hard ceiling instead of an age window
./scripts/reclaim-disk.sh --with-docker             # + prune stopped containers
cargo clean                         # nuclear option: ALL artifacts, a full rebuild follows
docker container prune
docker volume prune                 # testcontainers leaves volumes after interrupted runs
sudo btrfs balance start -musage=50 /   # root; reclaims metadata chunks (add -dusage=50 if data is fragmented too)
```

`cargo sweep` is a **local dev tool**, not a workspace dependency:

```bash
cargo install cargo-sweep --locked --version 0.8.0
```

`reclaim-disk.sh` **reports by default and only deletes with `--apply`** — the
same discipline as `reset-dev-data.sh` (`--dry-run` / `--no-backup`). It also
refuses to prune docker *volumes*, because the dev stack's data lives there
(`--with-docker` prunes stopped *containers* only).

Observed on the reference machine (2026-11-03): `target/` had grown to **857 GB**
(`target/debug/deps` 322 GB, `target/debug/incremental` **534 GB** — one
incremental cache directory per crate/feature/test combination, which cargo never
collects), on a 950 GB disk. `cargo clean` of a 1.3 TB `target/` removed ~125k
files in ~7 min here and took `Metadata,DUP` from 93% back to 40%. In CI set
`CARGO_INCREMENTAL=0` — CI
runners are ephemeral and do not benefit from incremental state.

**Containers are a second, invisible hog.** A container whose client died (an
interrupted `docker run`, a timing-out `docker cp`/`cp -a`) keeps running and its
writable layer stays on disk: a `python:3.12-slim` container that had copied a
build tree into itself held **601 GB** while `df` blamed the Rust build. `docker
ps --size` / `docker system df` show it; `reclaim-disk.sh` flags any container
above `CONTAINER_WARN_GB` (default 20 GB).

## Measurement note

Measure a representative harness (e.g. `handlers`) with `time cargo test -p api
--test handlers --no-run` after `touch`ing the harness, on a warm dependency
cache. Record before/after in the PR. The original 26–40 min figures and the
`ld` SIGBUS are documented in issue #631.
