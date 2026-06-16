# ADR-005: Use Axum as Web Framework

**Status**: Accepted  
**Date**: 2024-01-16  
**Author**: Initial Architecture Decision

---

## Context

Breakdown RS needs a web framework for the API layer (`crates/api`) that:
- **Integrates well with Rust async ecosystem**: Tokio, Tower, Hyper
- **Supports middleware**: Logging, CORS, authentication
- **Type-safe routing**: Compile-time checked routes
- **Good error handling**: Extractors, custom rejection handling
- **Extensible**: Easy to add WebSocket support later (for real-time updates)
- **Ecosystem**: Active maintenance, good documentation

### Alternatives considered:
- **Actix-web**: Popular but different async runtime (Actix), steeper learning curve
- **Rocket**: Opinionated, requires nightly Rust (historically)
- **Warp**: Good but complex filter system, less intuitive
- **Poem**: Newer, less mature ecosystem

## Decision

We will use **Axum** as the web framework for the API layer.

### Why Axum?

- ✅ **Built on Tower/Hyper**: Leverages mature ecosystem (used by Cloudflare, AWS)
- ✅ **Type-safe routing**: Extractors and handlers checked at compile time
- ✅ **Tokio-native**: Uses Tokio runtime (no conflicts with `kameo` actors)
- ✅ **Middleware via Tower**: Standardized, reusable middleware (CORS, auth, logging)
- ✅ **Ergonomic**: Clean API, easy to learn, good error messages
- ✅ **WebSocket support**: First-class support for real-time features
- ✅ **Active maintenance**: Maintained by Tokio team

### Example: Handler in Axum

```rust
use axum::{
    extract::{Path, Json, State},
    routing::{get, post},
    Router,
};

// Type-safe route definition
let app = Router::new()
    .route("/api/scenes", get(list_scenes).post(create_scene))
    .route("/api/scenes/:id", get(get_scene).delete(delete_scene))
    .with_state(app_state);  // Dependency injection

// Handler with extractors
async fn create_scene(
    State(state): State<AppState>,
    Json(payload): Json<CreateSceneCommand>,
) -> Result<Json<SceneDto>, AppError> {
    // ...
}
```

## Consequences

### Positive
- ✅ **Compile-time safety**: Routing errors caught at compile time, not runtime
- ✅ **Ecosystem integration**: Works seamlessly with `tower-http` (CORS, auth, tracing)
- ✅ **Async performance**: Built on Tokio, excellent performance
- ✅ **Type-driven design**: Extractors enforce request validation at type level
- ✅ **Middleware reuse**: Tower services can be reused across projects
- ✅ **WebSocket ready**: Easy to add real-time updates later (SSE, WebSocket)

### Negative
- ⚠️ **Learning curve**: Extractors and state management take time to understand
- ⚠️ **Less "magic"**: More boilerplate than Rocket (but more explicit)
- ⚠️ **Younger than Actix**: Actix has more users/history (but Axum is maturing fast)

### Mitigation
- Document common patterns in `AGENTS.md`
- Create reusable extractors for auth, validation
- Use `axum-extra` for additional utilities

## Alternatives Considered

### 1. Actix-web
- **Pros**: Mature, fast, large ecosystem
- **Cons**: 
  - Uses Actix runtime (not Tokio) → potential conflicts with `kameo` (Tokio-based)
  - Steeper learning curve (Actor-based middleware)
  - More boilerplate for extraction
- **Why not**: Runtime conflict risk, less type-safe routing

### 2. Rocket
- **Pros**: Ergonomic, opinionated, easy to start
- **Cons**: 
  - Historically required nightly Rust (now stable, but legacy perception)
  - Less flexible for complex middleware
- **Why not**: Less control over middleware stack

### 3. Warp
- **Pros**: Type-safe, functional style
- **Cons**: 
  - Complex filter composition (hard to read)
  - Less intuitive for teams
- **Why not**: Steep learning curve, less idiomatic

### 4. Poem
- **Pros**: OpenAPI integration, ergonomic
- **Cons**: Newer, smaller ecosystem
- **Why not**: Riskier for long-term maintenance

## Integration with Architecture

### How Axum fits in Hexagonal Architecture:

```
HTTP Request → Axum Handler → Command/Query → Aggregate/Projection
                     ↓
              Response (DTO) ← JSON Serialization
```

- **Handlers**: Thin layer, only translate HTTP → Domain
- **State**: `AppState` holds `CommandDispatcher`, `QueryHandler` (from core)
- **Extractors**: Validate input, convert to Commands/Queries
- **Responses**: Return DTOs (never domain models)

### Example: Command Dispatch

```rust
async fn create_scene(
    State(dispatcher): State<CommandDispatcher>,
    Json(cmd): Json<CreateSceneCommand>,
) -> Result<Json<SceneDto>, AppError> {
    // Dispatch command to aggregate (via kameo)
    let event = dispatcher.dispatch(cmd).await?;
    
    // Return DTO from read model (or event data)
    let dto = query_scene(event.scene_id).await?;
    Ok(Json(dto))
}
```

## Dependencies (Cargo.toml)

```toml
[dependencies]
axum = "0.7"
axum-extra = { version = "0.9", features = ["typed-routing"] }
tower = "0.4"
tower-http = { version = "0.5", features = ["cors", "trace", "auth"] }
tokio = { version = "1.35", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
```

## Notes

- **Version**: Use Axum 0.7+ (latest stable)
- **Tower middleware**: Use `tower-http` for CORS, logging, timeout
- **Error handling**: Implement `IntoResponse` for custom error types
- **Testing**: Use `axum::body::Body` and `tower::ServiceExt` for integration tests

### Resources
- [Axum Documentation](https://docs.rs/axum/latest/axum/)
- [Axum Examples](https://github.com/tokio-rs/axum/tree/main/examples)
- [Tower Guide](https://github.com/tower-rs/tower)

---

**Related ADRs**:
- [ADR-001: Use Hexagonal Architecture](./ADR-001-hexagonal-architecture.md)
- [ADR-006: Authentication and Authorization Strategy](./ADR-006-auth-strategy.md) *(planned)*

**Next Steps**:
- Set up Axum in `crates/api`
- Define first routes (scenes, costumes)
- Add CORS and logging middleware
