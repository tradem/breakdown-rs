# ADR-011: Observability with OpenTelemetry (Tracing & Logging)

**Status**: Proposed
**Date**: 2026-06-17
**Author**: Architecture Decision

---

## Context

Breakdown RS is a distributed system with multiple components: a Rust backend (Axum), a Svelte web frontend, and a future Flutter mobile app. As the system grows, we need comprehensive observability to:

- **Debug distributed workflows**: Track requests as they flow through CQRS commands, event handlers, and projections
- **Monitor performance**: Identify bottlenecks in command processing and event sourcing
- **Correlate logs across services**: Link frontend user actions with backend processing
- **Standardize telemetry**: Use industry standards to avoid vendor lock-in for observability tools

### Specific Challenges:
- CQRS event sourcing makes debugging complex (commands → events → projections)
- Multiple frontend clients (web + mobile) need consistent tracing
- Mono-repository setup offers opportunities for shared telemetry configuration
- Need to balance tracing detail with performance overhead

## Decision

We will adopt **OpenTelemetry (OTel)** as the standard for observability across all Breakdown RS components, with the following architectural decisions:

### 1. **OpenTelemetry as Unified Standard**
- Use OTel for **distributed tracing**, **metrics**, and **structured logging**
- Export telemetry data to an **OTel Collector** for processing and routing to backends (Jaeger, Prometheus, etc.)
- All components (Rust backend, Svelte frontend, Flutter app) will use OTel SDKs

### 2. **Rust Backend: `tracing` + `tracing-opentelemetry`**
- Use the `tracing` crate (Rust's standard instrumentation framework) with OTel exporter
- Integrate tracing spans with **CQRS command execution** and **event sourcing**
- Automatic instrumentation for Axum HTTP requests via `tracing-axum`
- Manual instrumentation for domain logic (commands, aggregates, projections)

### 3. **Mono-Repo Advantages for Telemetry**
- Shared OTel Collector configuration in `shared/infrastructure/otel-collector-config.yaml`
- Centralized Docker Compose setup for local observability stack (OTel Collector + Jaeger + Prometheus)
- Consistent span naming and attribute conventions across all components
- `just` commands to start/stop the full observability stack

### 4. **Local Development Stack**
- **OTel Collector**: Receives telemetry from all components, exports to:
  - **Jaeger**: Distributed tracing UI (spans, traces, dependencies)
  - **Prometheus**: Metrics storage
  - **Stdout**: Development logs (when debugging)
- Started via `just observability-up` (Docker Compose)

## Consequences

### Positive
- ✅ **Standardized Telemetry**: OTel is vendor-neutral; can switch backends (Jaeger → Tempo, etc.) without code changes
- ✅ **CQRS Observability**: Trace a command from HTTP request → aggregate → event → projection in a single Jaeger trace
- ✅ **Cross-Component Traces**: Frontend user actions correlated with backend processing via `traceparent` headers
- ✅ **Mono-Repo Synergy**: Shared configs, unified `just` commands, consistent conventions
- ✅ **Rust Ecosystem Maturity**: `tracing` + `tracing-opentelemetry` is production-ready and widely adopted

### Negative
- ⚠️ **Performance Overhead**: Tracing adds latency; need to configure sampling rates carefully
- ⚠️ **Complexity**: Developers must understand OTel concepts (spans, contexts, propagators)
- ⚠️ **Storage Costs**: Traces/metrics can grow quickly; need retention policies
- ⚠️ **Learning Curve**: Team must learn `tracing` instrumentation patterns in Rust

### Implementation Notes

#### Backend (Rust)
```rust
// Example: Tracing a CQRS command
#[instrument(skip(self, command), fields(command_type = "CreateScene"))]
async fn handle_create_scene(&self, command: CreateScene) -> Result<SceneCreated, DomainError> {
    let span = tracing::Span::current();
    span.set_attribute("scene.id", command.scene_id.to_string());

    // Command validation + event emission is automatically traced
    self.validate_and_emit(command).await
}
```

#### Frontend (Svelte)
- Use `@opentelemetry/web` or `@opentelemetry/svelte` for automatic HTTP instrumentation
- Propagate `traceparent` header in API requests to backend

#### Mono-Repo Structure
```
breakdown-rs/
├── shared/
│   └── infrastructure/
│       └── otel-collector-config.yaml  # Central OTel Collector config
├── docker-compose.observability.yml    # Jaeger + Prometheus + OTel Collector
└── Justfile                            # `just observability-up` command
```

## Alternatives Considered

1. **Manual Logging (no tracing standard)**:
   - ❌ No distributed tracing (can't follow requests across components)
   - ❌ Vendor lock-in (custom log formats)
   - **Why not chosen**: Insufficient for CQRS debugging

2. **Jaeger Direct Integration (without OTel)**:
   - ❌ Jaeger deprecated direct client libraries in favor of OTel
   - ❌ No metrics support (only tracing)
   - **Why not chosen**: OTel is the future standard

3. **Prometheus Only (metrics without traces)**:
   - ❌ No distributed tracing (can't debug CQRS flows)
   - ❌ Limited debugging capability
   - **Why not chosen**: Need both metrics and traces for full observability

4. **Cloud-Native (Datadog, New Relic)**:
   - ❌ Vendor lock-in (proprietary SDKs)
   - ❌ Expensive at scale
   - **Why not chosen**: Want to stay with open standards; can export to these later if needed

## Notes

### OpenTelemetry Collector Configuration
The OTel Collector acts as a central hub:
- **Receivers**: OTLP (gRPC + HTTP) from all components
- **Processors**: Batch, attributes, resource detection
- **Exporters**: Jaeger (traces), Prometheus (metrics), Logging (debug)

### Sampling Strategy
- **Development**: 100% sampling (debug everything)
- **Production**: Adaptive sampling (e.g., 10% base + 100% for errors)
- Configure via OTel Collector environment variables

### CQRS-Specific Tracing
Special attention needed for event sourcing:
- **Command Span**: Covers validation → event emission
- **Event Handler Span**: Covers event processing → projection update
- Use `trace_id` from command span as `parent_span_id` for event handlers

### References
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/)
- [tracing crate (Rust)](https://docs.rs/tracing/latest/tracing/)
- [tracing-opentelemetry](https://docs.rs/tracing-opentelemetry/latest/tracing_opentelemetry/)
- [OTel Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Jaeger UI](https://www.jaegertracing.io/)

---

**Related ADRs**:
- ADR-005: Use Axum (HTTP instrumentation via `tracing-axum`)
- ADR-006: utoipa OpenAPI Codegen (API endpoints will be traced)

**Follow-up Actions**:
- [ ] Add `tracing`, `tracing-opentelemetry`, `opentelemetry-otlp` to `Cargo.toml`
- [ ] Create `shared/infrastructure/otel-collector-config.yaml`
- [ ] Add `docker-compose.observability.yml` to mono-repo root
- [ ] Instrument Axum HTTP layer with `tracing-axum`
- [ ] Add `#[instrument]` macros to CQRS command handlers
- [ ] Document OTel setup in `AGENTS.md`
- [ ] Add `just observability-up` and `just observability-down` commands
