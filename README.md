# breakdown-rs

🦀 A modern, collaborative costume and scene continuity breakdown app built with Rust and PostgreSQL.

## Quality Gates

### 🦀 Backend

- [![CI](https://github.com/tradem/breakdown-rs/actions/workflows/ci.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/ci.yml)
- [![Architecture Checks](https://github.com/tradem/breakdown-rs/actions/workflows/architecture-checks.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/architecture-checks.yml)
- [![Security Audit](https://github.com/tradem/breakdown-rs/actions/workflows/audit.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/audit.yml)
- [![Mutation Testing](https://github.com/tradem/breakdown-rs/actions/workflows/mutation-testing.yml/badge.svg)](https://github.com/tradem/breakdown-rs/actions/workflows/mutation-testing.yml)

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
cargo run -p api
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
