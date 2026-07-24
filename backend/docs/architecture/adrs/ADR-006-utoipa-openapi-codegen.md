# ADR-006: Use utoipa for OpenAPI Specification and Frontend Code Generation

**Status**: Proposed
**Date**: 2026-06-17
**Author**: Tobias Rademacher (@tradem)

---

## Context

Breakdown RS needs a reliable way to generate and maintain API documentation that stays in sync with the actual implementation. Additionally, we want to generate type-safe client code for our frontend applications (TypeScript/JavaScript) to ensure compile-time safety and reduce integration errors.

### Problems we're facing:
- **API Documentation**: Manual API documentation becomes outdated quickly
- **Frontend-Backend Contract**: No formal contract between backend and frontend teams
- **Type Safety**: Frontend developers manually create TypeScript types, leading to drift
- **Validation**: No centralized request/response validation based on the API spec
- **Onboarding**: New developers need up-to-date API docs to be productive

### Requirements:
- OpenAPI 3.0+ specification generation from Axum handlers
- Automatic synchronization between code and documentation
- Code generation for TypeScript/JavaScript frontends
- Request/response validation against the OpenAPI spec
- IDE support (auto-completion, inline documentation)

### Alternatives considered:
- **Manual OpenAPI spec**: Error-prone, gets outdated
- **paperclip**: Good but less active maintenance, macro-heavy
- **OKAPI**: Focused on Swagger UI, less flexible
- **Hand-written types**: No guarantees, manual synchronization

## Decision

We will use **utoipa** to automatically generate OpenAPI 3.0 specifications from our Axum handlers and use the generated spec for frontend code generation.

### Why utoipa?

- ✅ **Compile-time generation**: OpenAPI spec generated at compile time, always in sync
- ✅ **Axum integration**: First-class support for Axum via `utoipa-axum`
- ✅ **Minimal macros**: Uses derive macros, not invasive procedural macros
- ✅ **Type safety**: Leverages Rust's type system for schema generation
- ✅ **Flexible**: Supports complex schemas, enums, generics
- ✅ **Ecosystem**: Actively maintained, good documentation
- ✅ **Swagger UI**: Built-in support for serving Swagger UI (`utoipa-swagger-ui`)

### Example: Schema Definition

```rust
use utoipa::{ToSchema, IntoParams};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateSceneCommand {
    /// Name of the scene
    pub name: String,

    /// Description of the scene
    #[schema(example = "Act 1, Scene 3")]
    pub description: Option<String>,

    /// Production ID this scene belongs to
    pub production_id: Uuid,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SceneDto {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub production_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListScenesQuery {
    /// Filter by production ID
    pub production_id: Option<Uuid>,

    /// Maximum number of results
    #[param(default = 50, minimum = 1, maximum = 100)]
    pub limit: Option<i64>,

    /// Number of results to skip
    pub offset: Option<i64>,
}
```

### Example: Axum Handler with OpenAPI Derive

```rust
use axum::{Json, extract::{Path, Query, State}};
use utoipa_axum::{router::OpenApiRouter, routes};

/// Create a new scene
///
/// Creates a new scene in the specified production.
#[utoipa::path(
    post,
    path = "/api/scenes",
    request_body = CreateSceneCommand,
    responses(
        (status = 201, description = "Scene created successfully", body = SceneDto),
        (status = 400, description = "Invalid input"),
        (status = 500, description = "Internal server error")
    ),
    tag = "Scenes"
)]
async fn create_scene(
    State(dispatcher): State<CommandDispatcher>,
    Json(cmd): Json<CreateSceneCommand>,
) -> Result<(StatusCode, Json<SceneDto>), AppError> {
    // Implementation...
}

// Router setup with OpenAPI
let (router, api) = OpenApiRouter::new()
    .routes(routes!(create_scene))
    .routes(routes!(list_scenes))
    .routes(routes!(get_scene))
    .split_for_parts();

// Generate OpenAPI spec
let openapi = api.merge(utoipa::OpenApi::new());
let spec = openapi.to_json().unwrap();
```

### Example: Serving Swagger UI

```rust
use utoipa_swagger_ui::SwaggerUi;

let app = Router::new()
    .merge(
        SwaggerUi::new("/swagger-ui")
            .url("/api-docs/openapi.json", openapi)
    )
    .nest("/api", router);
```

## Frontend Code Generation

### Using openapi-generator

Once we have the OpenAPI spec (generated at compile time or served via `/api-docs/openapi.json`), we can use **openapi-generator** to generate TypeScript clients:

```bash
# Generate TypeScript fetch client
npx @openapitools/openapi-generator-cli generate \
  -i openapi.json \
  -g typescript-fetch \
  -o frontend/src/generated \
  --additional-properties=modelPropertyNaming=original,supportsES6=true
```

### Using swagger-codegen

Alternatively, use **swagger-codegen** for more customization:

```bash
docker run --rm \
  -v ${PWD}:/local \
  swaggerapi/swagger-codegen-cli generate \
  -i /local/openapi.json \
  -l typescript-axios \
  -o /local/frontend/src/generated
```

### Example Generated TypeScript

```typescript
// Generated from OpenAPI spec
export interface SceneDto {
  id: string;
  name: string;
  description?: string;
  production_id: string;
  created_at: string;
  updated_at: string;
}

export interface CreateSceneCommand {
  name: string;
  description?: string;
  production_id: string;
}

export class ScenesApi {
  async createScene(cmd: CreateSceneCommand): Promise<SceneDto> {
    // Auto-generated fetch/axios call
  }
}
```

## Consequences

### Positive
- ✅ **Always in sync**: OpenAPI spec generated at compile time, cannot drift from code
- ✅ **Type safety across boundaries**: Frontend types generated from backend types
- ✅ **Developer experience**: Swagger UI auto-generated, interactive API docs
- ✅ **IDE support**: Auto-completion for API endpoints in frontend
- ✅ **Validation**: Request/response validation can be added via middleware
- ✅ **Onboarding**: New developers can explore API via Swagger UI
- ✅ **Contract testing**: OpenAPI spec enables contract-based testing

### Negative
- ⚠️ **Compile time**: Macro expansion adds to compile time (mitigated by incremental compilation)
- ⚠️ **Learning curve**: Developers need to learn utoipa macros and attributes
- ⚠️ **Macro complexity**: Debugging macro-generated code can be challenging
- ⚠️ **Code generation dependency**: Frontend build depends on backend OpenAPI spec

### Mitigation
- Document utoipa patterns in `AGENTS.md`
- Create helper macros for common patterns
- Set up CI to validate OpenAPI spec generation
- Use `utoipa`'s `#[schema(...)]` attributes consistently
- Generate TypeScript types in a pre-build step

### Trade-offs
- **Macro-heavy**: More compile-time magic, but type safety guaranteed
- **OpenAPI compliance**: Limited by utoipa's OpenAPI 3.0 support (no 3.1 yet)
- **Frontend coupling**: Frontend build process depends on backend OpenAPI spec

## Integration with Architecture

### How utoipa fits in Hexagonal Architecture:

```
Rust Types (core) → utoipa Schema → OpenAPI Spec → Generated TypeScript (frontend)
        ↓                                                            ↑
Axum Handlers (api) → utoipa-axum → OpenAPI Spec (JSON) ───────────┘
```

- **Schema types**: Defined in `core` (DTOs), derive `ToSchema`
- **Handlers**: In `crates/api`, annotate with `#[utoipa::path(...)]`
- **Spec generation**: At compile time or runtime via `utoipa-swagger-ui`
- **Frontend**: Generate TypeScript from `/api-docs/openapi.json`

### Example: Full Workflow

1. **Define DTO** (in `core`):
   ```rust
   #[derive(Serialize, Deserialize, ToSchema)]
   pub struct SceneDto { ... }
   ```

2. **Implement handler** (in `api`):
   ```rust
   #[utoipa::path(get, path = "/scenes/{id}", responses((status = 200, body = SceneDto)))]
   async fn get_scene(...) -> Json<SceneDto> { ... }
   ```

3. **Generate spec** (compile time):
   ```rust
   let openapi = OpenApiBuilder::new()
       .meta(InfoBuilder::new().title("Breakdown RS API").build())
       .paths(routes!(get_scene, create_scene))
       .build();
   ```

4. **Generate frontend code** (build step):
   ```bash
   cargo run --bin generate-openapi > openapi.json
   npx openapi-generator generate -i openapi.json -g typescript-fetch -o frontend/src/generated
   ```

## Dependencies (Cargo.toml)

```toml
[dependencies]
# Existing Axum dependencies...
axum = "0.7"
serde = { version = "1.0", features = ["derive"] }

# utoipa for OpenAPI generation
utoipa = { version = "4.0", features = ["axum_extras"] }
utoipa-axum = "4.0"
utoipa-swagger-ui = { version = "4.0", features = ["axum"] }

# Optional: Generate OpenAPI spec at compile time
utoipa-gen = "4.0"  # Only if using compile-time generation
```

### Dev Dependencies

```toml
[dev-dependencies]
# Validate OpenAPI spec in tests
utoipa::OpenApi;  # Trait for spec validation
```

## Alternatives Considered

### 1. paperclip
- **Pros**: Similar to utoipa, good Axum support
- **Cons**:
  - Less active maintenance (fewer releases)
  - More macro-heavy, harder to debug
  - Smaller community
- **Why not**: utoipa has better documentation and more active maintenance

### 2. OKAPI
- **Pros**: Good Swagger UI integration
- **Cons**:
  - Less flexible schema definition
  - Primarily focused on Swagger UI, not code generation
- **Why not**: utoipa provides better code generation workflow

### 3. Manual OpenAPI Spec (YAML/JSON)
- **Pros**: Full control, no macros
- **Cons**:
  - Gets outdated immediately
  - Duplication between types and spec
  - No compile-time guarantees
- **Why not**: Defeats the purpose of type-safe Rust

### 4. GraphQL (instead of REST + OpenAPI)
- **Pros**: Type-safe by default, great tooling
- **Cons**:
  - Major architectural shift (away from REST)
  - Learning curve for team
  - Overkill for CRUD operations
- **Why not**: Too big a change, REST + OpenAPI is sufficient

## Implementation Plan

### Phase 1: Basic Setup
1. Add `utoipa`, `utoipa-axum`, `utoipa-swagger-ui` to `crates/api`
2. Derive `ToSchema` for existing DTOs in `core`
3. Annotate one handler with `#[utoipa::path(...)]`
4. Serve Swagger UI at `/swagger-ui`

### Phase 2: Full Integration
1. Annotate all handlers with OpenAPI attributes
2. Set up OpenAPI spec generation in `main.rs`
3. Document all request/response types
4. Add examples to schema attributes

### Phase 3: Frontend Code Generation
1. Set up OpenAPI spec export endpoint (`/api-docs/openapi.json`)
2. Configure `openapi-generator` for TypeScript
3. Add pre-build step to generate frontend types
4. Validate generated types in CI

### Phase 4: Validation (Optional)
1. Add request validation middleware (validate against OpenAPI spec)
2. Add response validation in tests
3. Set up contract testing between frontend and backend

## Notes

### Best Practices
- **Always add examples**: Use `#[schema(example = "...")]` for better Swagger UI docs
- **Use enums**: Represent constrained values as enums (utoipa generates them correctly)
- **Document errors**: Use `responses(...)` to document all possible error codes
- **Tag organization**: Use `tag = "..."` to group endpoints in Swagger UI
- **Reuse schemas**: Define schemas once, reference them via `$ref`

### Common Pitfalls
- **Circular types**: utoipa may fail on circular type definitions (use `#[schema(untagged)]`)
- **Generic types**: Need to implement `ToSchema` for concrete type parameters
- **Option<T>**: Handled automatically, but document with `required: false` explicitly

### Resources
- [utoipa Documentation](https://docs.rs/utoipa/latest/utoipa/)
- [utoipa-axum Examples](https://github.com/juhaku/utoipa/tree/master/examples)
- [OpenAPI 3.0 Specification](https://swagger.io/specification/)
- [openapi-generator](https://openapi-generator.tech/)
- [TypeScript Fetch Client](https://github.com/openapitools/openapi-generator/tree/master/modules/openapi-generator/src/main/resources/typescript-fetch)

### CI Integration

```yaml
# .github/workflows/openapi.yml
- name: Generate OpenAPI spec
  run: cargo run --bin generate-openapi > openapi.json

- name: Validate OpenAPI spec
  run: npx @apidevtools/swagger-cli validate openapi.json

- name: Generate TypeScript types
  run: npx @openapitools/openapi-generator-cli generate -i openapi.json -g typescript-fetch -o frontend/src/generated

- name: Upload OpenAPI spec as artifact
  uses: actions/upload-artifact@v3
  with:
    name: openapi-spec
    path: openapi.json
```

---

**Related ADRs**:
- [ADR-005: Use Axum as Web Framework](./ADR-005-use-axum.md)
- [ADR-001: Use Hexagonal Architecture](./ADR-001-hexagonal-architecture.md)

**Next Steps**:
1. Add utoipa dependencies to `crates/api/Cargo.toml`
2. Derive `ToSchema` for DTOs in `crates/core`
3. Annotate first handler with `#[utoipa::path(...)]`
4. Set up Swagger UI endpoint
5. Document utoipa patterns in `AGENTS.md`

**Status**: This ADR is ready for review and implementation. Once accepted, we will proceed with Phase 1 of the implementation plan.
