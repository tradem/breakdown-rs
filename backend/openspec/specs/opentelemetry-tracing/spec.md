# Purpose

Define the OpenTelemetry tracing integration for the Breakdown RS API binary: OTLP trace export driven by `OTEL_*` environment variables, composable with the existing `tracing_subscriber::fmt` layer, and HTTP request-level tracing via `tower-http`. Metrics and log export are out of scope.

# Requirements

### Requirement: API exports OpenTelemetry traces via OTLP
The API binary SHALL register an OpenTelemetry OTLP trace exporter when the `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable is set to a non-empty value. When the endpoint is unset or empty, no OTLP exporter SHALL be created and the system SHALL continue to emit formatted tracing output to stderr only.

#### Scenario: OTLP endpoint configured
- **WHEN** the API starts with `OTEL_EXPORTER_OTLP_ENDPOINT` set to a valid collector URL (e.g., `http://otel-collector:4317`)
- **THEN** an OpenTelemetry `TracerProvider` with an OTLP exporter is registered as a `tracing-subscriber` layer
- **AND** spans produced by the application are exported to the configured endpoint

#### Scenario: OTLP endpoint not configured (local dev)
- **WHEN** the API starts without `OTEL_EXPORTER_OTLP_ENDPOINT` set, or set to an empty string
- **THEN** no OTLP exporter is created
- **AND** tracing output is written to stderr via the `fmt` subscriber only

### Requirement: HTTP requests produce tracing spans
Every incoming HTTP request handled by the Axum router SHALL produce a `tracing` span that includes the HTTP method, request URI, response status code, and request latency.

#### Scenario: Successful HTTP request
- **WHEN** an HTTP GET request is made to `/api/scenes`
- **THEN** a `tracing` span is created with `http.method = GET`, `http.uri = /api/scenes`, `http.status_code = 200`, and a latency field
- **AND** the span is emitted to all active subscribers (fmt and/or OTLP)

#### Scenario: Failed HTTP request
- **WHEN** an HTTP POST request to `/api/scenes` fails with a 422 status
- **THEN** a `tracing` span is created with `http.status_code = 422`
- **AND** the span is emitted to all active subscribers

### Requirement: OpenTelemetry environment variables are respected
The OTLP exporter configuration SHALL be driven by the following environment variables as declared in `docker-compose.prod.yml`: `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, and `OTEL_TRACES_EXPORTER`.

#### Scenario: Service name set via environment
- **WHEN** the API starts with `OTEL_SERVICE_NAME=breakdown-rs`
- **THEN** exported spans carry the service name `breakdown-rs`

#### Scenario: OTLP protocol set to HTTP/protobuf
- **WHEN** `OTEL_EXPORTER_OTLP_PROTOCOL` is set to `http/protobuf`
- **THEN** the OTLP exporter uses the HTTP/protobuf transport (not gRPC)

### Requirement: Fmt subscriber and OTLP subscriber coexist
When both subscribers are active, the system SHALL use a composable `tracing_subscriber::registry()` so that spans are delivered to both the fmt layer (stderr) and the OTLP layer simultaneously, without one blocking the other.

#### Scenario: Both subscribers active
- **WHEN** the API starts with `OTEL_EXPORTER_OTLP_ENDPOINT` set to a valid URL
- **THEN** each span is received by both the fmt subscriber and the OTLP exporter
- **AND** a failure in the OTLP exporter does not prevent formatted output to stderr
