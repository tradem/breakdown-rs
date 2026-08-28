## Context

The production `docker-compose.prod.yml` sets five `OTEL_*` environment variables on the API service (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_TRACES_EXPORTER`, `OTEL_METRICS_EXPORTER`). ADR-016 task 3.3 declares these as "consumed by the API binary and the `tracing-opentelemetry` subscriber." However, `crates/api/src/main.rs` only calls `tracing_subscriber::fmt::init()` — a single-layer fmt subscriber with no OTLP export. The `tracing-opentelemetry` and `opentelemetry-otlp` crates are absent from `Cargo.toml`. The env vars are therefore inert; no traces reach an observability backend.

The target observability architecture is: local dev uses stderr/formatted output only (current behavior); staging/production, when `OTEL_EXPORTER_OTLP_ENDPOINT` is set, additionally exports spans via OTLP/gRPC or OTLP/HTTP to an OpenTelemetry collector.

## Goals / Non-Goals

**Goals:**
- Wire `tracing-opentelemetry` + `opentelemetry-otlp` into the API binary, configured from existing `OTEL_*` env vars
- Layer the OTLP subscriber on top of the existing fmt subscriber via `tracing_subscriber::registry()`
- Add `tower-http` `TraceLayer` to the Axum router so each HTTP request produces a root span with method, URI, status, and latency
- Keep local dev unchanged: no OTEL endpoint → no OTLP exporter → same fmt-only output as today
- Update `Cargo.toml` workspace dependencies and `crates/api/Cargo.toml`

**Non-Goals:**
- Metrics export (the `tracing-opentelemetry` subscriber handles traces; `OTEL_METRICS_EXPORTER` is set to `otlp` in compose but metric export via `opentelemetry_sdk::metrics` is a separate concern deferred to a follow-up)
- Log export (OTEL_LOGS_EXPORTER=none in compose, no change)
- Custom span processors, sampling strategies, or baggage propagation beyond defaults
- SierraDB or Postgres query-level instrumentation (out of scope for this change)
- Changing the docker-compose files or ADRs beyond updating ADR-016 task 3.3 wording

## Decisions

### Decision 1: Use `tracing-opentelemetry` with `opentelemetry-otlp` crate

**Choice**: `tracing-opentelemetry` 0.28 + `opentelemetry-otlp` 0.27 (with `http-proto` or `tonic` transport).

**Rationale**: These are the standard crates bridging the `tracing` ecosystem to OpenTelemetry. `opentelemetry-otlp` supports both gRPC (`tonic` feature) and HTTP/protobuf (`http-proto` feature) via the `OTEL_EXPORTER_OTLP_PROTOCOL` env var. The `tracing-opentelemetry` layer plugs directly into `tracing_subscriber::registry()`.

**Alternatives considered**:
- `opentelemetry-application-insights` / vendor-specific exporters — rejected; OTLP is vendor-neutral and matches the compose declarations
- Manual span export via custom layer — unnecessary complexity
- `opentelemetry_sdk` with only the trace provider (no metrics) — accepted as the initial scope; metrics provider deferred

### Decision 2: Compose subscribers with `tracing_subscriber::registry()` not `set_global_default`

**Choice**: Use `tracing_subscriber::registry().with(fmt_layer).with(otel_layer).init()`.

**Rationale**: `registry()` allows multiple `Layer` implementations to coexist. The current `fmt::init()` is a convenience that sets a single layer as global default. Moving to `registry()` preserves fmt output and adds OTLP when configured. This is the documented pattern for combining `tracing-opentelemetry` with other subscribers.

### Decision 3: OTLP layer is conditionally built

**Choice**: Check `OTEL_EXPORTER_OTLP_ENDPOINT` at startup: if empty or unset, skip building the OTLP layer entirely. Log a message indicating OTLP is disabled.

**Rationale**: Avoids requiring an OTLP collector in local dev. The compose files set the default to empty string; user must explicitly configure a collector endpoint.

### Decision 4: Use `tower-http` TraceLayer for HTTP spans

**Choice**: Add `tower-http` with `trace` feature; wrap the Axum router with `TraceLayer::new_for_http()`.

**Rationale**: `tower-http`'s `TraceLayer` integrates with the `tracing` crate, producing spans with `http.method`, `http.uri`, `http.status_code`, and latency for every request. This is the standard Axum observability pattern and adds no extra allocation overhead per request.

### Decision 5: Keep `OTEL_METRICS_EXPORTER=otlp` as future hook

**Choice**: Do not wire metrics export in this change; only trace export. The env var remains documented but non-functional until a follow-up.

**Rationale**: Metrics require significantly more scaffolding (meter provider, periodic reader, metric instruments). Traces provide the highest observability ROI first. The env var surface is already declared and accepted.

## Risks / Trade-offs

- **Risk**: `tracing-opentelemetry` / `opentelemetry-otlp` version incompatibility with the existing `tracing` 0.1 and `tracing-subscriber` 0.3 → **Mitigation**: Pin compatible versions; cargo update will test resolution. Known compatible range: `tracing-opentelemetry` 0.28 works with `tracing` 0.1.
- **Risk**: OTLP batch export failing silently (collector unreachable) → **Mitigation**: The default retry/batch behavior drops spans after a timeout; add a `warn!` log when the exporter error channel fires (via `opentelemetry_sdk::runtime::Tokio`).
- **Risk**: Performance overhead from TraceLayer on every request → **Mitigation**: `TraceLayer::new_for_http()` is lightweight (two `tracing` span macro invocations per request). No dynamic dispatch or allocation beyond the span's metadata. Negligible impact on p99 latency.
- **Trade-off**: Metrics deferred → observability is partial until follow-up. Acceptable because trace-first is standard rollout order.

## Open Questions

- Should we add a `tracing` span to the `sqlx` query layer or kameo command execution? (Deferred; current scope is HTTP-level only.)
- Should sampling rate be configurable? (OTEL defaults to always-on; no sampling config added in this change.)
