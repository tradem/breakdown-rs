## 1. Dependencies

- [x] 1.1 Add `tracing-opentelemetry`, `opentelemetry-otlp`, `opentelemetry_sdk`, and `tower-http` to `[workspace.dependencies]` in root `Cargo.toml`
- [x] 1.2 Add `tracing-opentelemetry`, `opentelemetry-otlp`, `opentelemetry_sdk`, and `tower-http` (with `trace` feature) to `crates/api/Cargo.toml`

## 2. Subscriber wiring

- [x] 2.1 Replace `tracing_subscriber::fmt::init()` in `main.rs` with a `tracing_subscriber::registry()` that layers `fmt` and (conditionally) `opentelemetry_otlp`
- [x] 2.2 Implement conditional OTLP layer: only build the `OpenTelemetryLayer` when `OTEL_EXPORTER_OTLP_ENDPOINT` is non-empty; log a `warn!` or `info!` when OTLP is disabled
- [x] 2.3 Configure the OTLP exporter to read `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, and `OTEL_TRACES_EXPORTER` from the environment
- [x] 2.4 Add an error-channel handler that logs `warn!` when the OTLP batch exporter encounters errors (collector unreachable, etc.)

## 3. HTTP instrumentation

- [x] 3.1 Add `tower_http::trace::TraceLayer` to the Axum router in `main.rs` (or `app_router()`), using `TraceLayer::new_for_http()`
- [x] 3.2 Verify that spans include `http.method`, `http.uri`, `http.status_code`, and latency — `TraceLayer::new_for_http()` provides these by default

## 4. Validation

- [x] 4.1 Verify local dev mode: start the API without `OTEL_EXPORTER_OTLP_ENDPOINT`, confirm fmt output unchanged and no OTLP connection attempts
- [x] 4.2 Verify OTLP mode: start the API with `OTEL_EXPORTER_OTLP_ENDPOINT` pointing to a local collector (e.g., Jaeger), confirm traces appear
- [x] 4.3 Run existing tests (`cargo test -p api`, `cargo test -p integration-tests`) to ensure no regressions

## 5. Documentation

- [x] 5.1 Update ADR-016 task 3.3 wording from "wired for both tiers" to reflect implemented status (OTLP trace export functional, metrics deferred)
