# breakdown-rs

🦀 A modern, collaborative costume and scene continuity breakdown app built with Rust and PostgreSQL.

## Development

### Prerequisites

- [Rust](https://rustup.rs/) (latest stable toolchain)
- [Docker](https://docs.docker.com/get-docker/) or a compatible container runtime — required for the dev database and the Testcontainers-based integration test suite.

### Start the dev database

v1 ships a Postgres-only dev compose (SierraDB is deferred to the `sierradb-runtime-and-round-trip` follow-up):

```bash
cd backend
docker compose -f docker-compose.dev.yml up -d
```

Postgres is reachable at `postgres://postgres:postgres@localhost:5432/breakdown`.

### Apply migrations and run the API

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown cargo run -p api
```

The API serves OpenAPI/Swagger UI at `http://localhost:3000/swagger-ui`.

### Running integration tests locally

The black-box integration tests spin up an ephemeral PostgreSQL container per test. From the repository root run:

```bash
cargo test -p integration-tests
```

For details on the integration-test boundary, CI triggers, and local dev commands, see [`backend/AGENTS.md`](./backend/AGENTS.md).

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
