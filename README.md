<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# breakdown-rs

🦀 A modern, collaborative costume and scene continuity breakdown app built with Rust and PostgreSQL.

## Quality Gates

| Gate | Scope | Status |
|---|---|---|
| CI (format, clippy, tests, MSRV, deny) | 🦀 Backend | [![CI](https://github.com/tradem/breakdown-rs/actions/workflows/ci.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/ci.yml) |
| Architecture Checks (rust_arkitect, ast-grep, cargo-deny) | 🦀 Backend | [![Architecture Checks](https://github.com/tradem/breakdown-rs/actions/workflows/architecture-checks.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/architecture-checks.yml) |
| Security Audit (cargo-deny advisories, gitleaks) | 🦀 Backend | [![Security Audit](https://github.com/tradem/breakdown-rs/actions/workflows/audit.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/audit.yml) |
| Integration Tests (tiers 1–4, Testcontainers) | 🦀 Backend | [![Integration Tests](https://github.com/tradem/breakdown-rs/actions/workflows/integration-tests.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/integration-tests.yml) |
| Semver Checks (per-crate, ADR-020) | 🦀 Backend | [![Semver Checks](https://github.com/tradem/breakdown-rs/actions/workflows/semver-checks.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/semver-checks.yml) |
| Mutation Testing (CI-only, nightly) | 🦀 Backend | [![Mutation Testing](https://github.com/tradem/breakdown-rs/actions/workflows/mutation-testing.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/mutation-testing.yml) |
| Fuzz (nightly) | 🦀 Backend | [![Fuzz (nightly)](https://github.com/tradem/breakdown-rs/actions/workflows/fuzz-nightly.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/fuzz-nightly.yml) |
| Flutter CI (format, analyze, gitleaks, OpenAPI drift, coverage, Gherkin) | 📱 Frontend | [![Flutter CI](https://github.com/tradem/breakdown-rs/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/flutter-ci.yml) |
| Design Tokens Drift | 📱 Frontend | [![Design Tokens Drift](https://github.com/tradem/breakdown-rs/actions/workflows/design-tokens-drift.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/design-tokens-drift.yml) |
| Icon Drift (SVG ↔ adaptive launcher icons) | 📱 Frontend | [![Icon Drift](https://github.com/tradem/breakdown-rs/actions/workflows/icon-drift.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/icon-drift.yml) |
| Docs Design Lint (PlantUML screen specs) | 📱 Frontend | [![Docs Design Lint](https://github.com/tradem/breakdown-rs/actions/workflows/docs-design-lint.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/docs-design-lint.yml) |

Release pipelines (tag-triggered, not gates): the `api` Docker image
(`api-vX.Y.Z` tags → `release-image.yml`) and the signed Android release
(`vX.Y.Z` tags → `flutter-release.yml`).

## Development

### Prerequisites

- [Rust](https://rustup.rs/) (latest stable toolchain)
- [Docker](https://docs.docker.com/get-docker/) or a compatible container runtime — required for the dev database and the Testcontainers-based integration test suite.

### Start the dev runtime (both tiers)

The dev compose starts the full two-tier stack (ADR-015 / ADR-016): Postgres for
the CQRS read-model projections **and** SierraDB for the RESP3 event store.

```bash
cd backend
docker compose -f docker-compose.dev.yml up -d
```

- Postgres is reachable at `postgres://postgres:postgres@localhost:5432/breakdown`.
- SierraDB (RESP3) is reachable at `redis://127.0.0.1:9090` (pinned to `tqwewe/sierradb:0.3.1`).

### Optional: IdP Overlay for Auth Development

For auth-related work (OIDC flows), boot the optional IdP overlay:

```bash
cd backend
docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d
./scripts/seed-logto-dev.sh  # Generates .env.idp with OIDC configuration
```

This adds a self-hosted Logto IdP (`http://localhost:3301`) for local OIDC testing.
**Dev-only** — production IdP is separate (see [AGENTS.md](./backend/AGENTS.md)).

### Apply migrations and run the API

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 \
cargo run --bin api
```

`main.rs` applies the Postgres projection migrations at boot, opens a RESP3
connection to SierraDB, and spawns the projectors that keep the Postgres
projections in sync with the event store.

The API serves OpenAPI/Swagger UI at `http://localhost:3000/swagger-ui`.

### Running integration tests locally

The black-box integration tests spin up ephemeral containers per test. Tier 1–3
tests use Postgres only; Tier-4 tests (ADR-016) run the full
`command → SierraDB → projector → Postgres` round-trip against both a SierraDB
and a Postgres container. From the repository root run:

```bash
cargo test -p integration-tests
```

Requires Docker (or a compatible container runtime); Tier-4 tests additionally
pull the `tqwewe/sierradb:0.3.1` image. For details on the integration-test
boundary, CI triggers, and local dev commands, see [`backend/AGENTS.md`](./backend/AGENTS.md).

## Design documentation

Design docs live under `docs/design/`: screen specs
(`docs/design/screens/<screen-name>.md`, authored in the same OpenSpec
change that implements the screen), the icon/terminology glossary
(`docs/design/glossary.md`), and the UI/UX research report. Every
screen change must author or update its screen spec **before** the
implementation tasks; the `design-wireframe-salt` pi skill
(`frontend-flutter/.pi/skills/design-wireframe-salt/`) drives the
format, and CI validates that all PlantUML blocks compile
(`scripts/check-design-diagrams.sh` → `.github/workflows/docs-design-lint.yml`).

## Self-hosting

`breakdown-rs` is AGPL-3.0 — you can run your own instance. The officially
published Android APK is deliberately bound to the project-operated backend
(one binary = one instance), so self-hosters build an instance-owned APK from
source with their own backend URL, OIDC registration and pinned CA. See the
guide: [`frontend-flutter/docs/self-hosting.md`](./frontend-flutter/docs/self-hosting.md).

## License

This project is licensed under the [AGPL-3.0 License](LICENSE).

### What does AGPL mean?

The GNU Affero General Public License (AGPL) is a strong copyleft license that requires:
- **Source code disclosure**: If you modify this software, you must make the source code available
- **Network use**: If you run a modified version on a server (e.g., as a web service), you must provide the source code to users
- **Same license**: Derivative works must also be licensed under AGPL

This ensures that improvements to the software remain open and benefit the entire community.

### Why AGPL?

We chose AGPL because Breakdown RS is designed to be deployed as a web application. The AGPL closes the "SaaS loophole" of regular GPL, ensuring that even cloud deployments of modified versions contribute back to the open-source community.

## Contributing

Contributions are welcome! Please read our contributing guidelines (TODO: add link) and submit pull requests to our repository.

## Contact

- GitHub Issues: https://github.com/tradem/breakdown-rs/issues
- Discussions: https://github.com/tradem/breakdown-rs/discussions
