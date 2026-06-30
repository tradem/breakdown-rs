## Why

ADR-016 and `docker-compose.prod.yml` declare OpenTelemetry hooks as "wired for both tiers", with `OTEL_*` environment variables set on the API service. However, the API binary only initializes a `tracing_subscriber::fmt` subscriber — no `tracing-opentelemetry` OTLP exporter is registered, and the required crates are absent from `Cargo.toml`. This means the OTEL env vars are inert; no traces, metrics, or logs are exported to an observability backend. Closing this gap unblocks production observability and aligns the implementation with the documented architecture.

## What Changes

- Add `tracing-opentelemetry` and `opentelemetry-otlp` dependencies to the workspace and the `api` crate
- Wire an OpenTelemetry OTLP subscriber in `main.rs`, configured from the existing `OTEL_*` environment variables
- The OTLP exporter is opt-in: when `OTEL_EXPORTER_OTLP_ENDPOINT` is unset or empty, only the fmt subscriber is active (no breaking change)
- Add `tracing` spans to the Axum HTTP layer via `tower-http` trace middleware, producing request-level traces with method, path, status, and latency
- Update ADR-016 task 3.3 to reflect implementation status

## Capabilities

### New Capabilities

- `opentelemetry-tracing`: OpenTelemetry OTLP trace export from the API binary, driven by `OTEL_*` environment variables as declared in the production compose and ADR-016; includes request-level HTTP spans via `tower-http` trace middleware.

### Modified Capabilities

<!-- None: this is a new observability capability; no existing spec-level requirements change. -->

## Impact

- **Dependencies**: New workspace dependencies `tracing-opentelemetry`, `opentelemetry-otlp`, `opentelemetry_sdk`, and `tower-http` (trace feature)
- **API binary** (`crates/api/src/main.rs`): Subscriber initialization logic changes; a composable `tracing_subscriber::registry()` with layered `fmt` + `opentelemetry_otlp` subscriber replaces the single `fmt::init()` call
- **Observability contract**: The `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_TRACES_EXPORTER`, and `OTEL_METRICS_EXPORTER` env vars become functional
- **ADR-016**: Task 3.3 wording updated from "wired for both tiers" to reflect implemented status
- **No breaking changes**: Existing local dev flow (no OTEL endpoint set) continues to use fmt-only output
