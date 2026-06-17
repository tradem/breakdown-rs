# ADR-012: Error Handling with thiserror and anyhow in Axum

**Status**: Accepted  
**Date**: 2026-06-17  
**Author**: Architecture Decision

---

## Context

Breakdown RS needs a consistent and secure error-handling strategy for the API layer (`crates/api`) that:

- **Uniform error responses**: Clients always receive a consistent JSON format (e.g., `{ "error": "Error message" }`)
- **Security**: No sensitive error details (e.g., database errors) may leak to the client
- **Developer ergonomics**: Simple error handling in handlers via `?` operator
- **Observability**: Complete error chains in server logs for debugging purposes
- **Type safety**: Leverage Rust's type system to clearly distinguish domain errors

### Problem Statement

Without a centralized error-handling strategy, we face:
- Inconsistent error responses to clients
- Security risks from leaking internal details (DB errors, stack traces)
- Significant boilerplate code in handlers for error mapping
- Difficult debugging due to missing error chains

### Influencing Factors

- **Axum's `IntoResponse` trait**: Enables automatic conversion of errors into HTTP responses
- **`thiserror`**: Ergonomic definition of domain error types with `#[derive(Error)]`
- **`anyhow`**: Excellent error chaining (context) for unexpected/non-domain errors
- **`tracing`**: Already chosen for observability (see ADR-011)

## Decision

We implement a **hybrid error-handling strategy** with `thiserror` for domain errors and `anyhow` for internal errors, centralized in an `AppError` enum with Axum integration.

### Architecture Decision

```rust
// 1. Uniform error JSON for clients
#[derive(Serialize)]
struct ApiErrorPayload {
    error: String,
}

// 2. Central application error (thiserror + anyhow)
#[derive(thiserror::Error, Debug)]
pub enum AppError {
    #[error("Validation error: {0}")]
    BadRequest(String),

    #[error("Resource not found")]
    NotFound,

    #[error("Unauthorized")]
    Unauthorized,

    // Catch-all for unexpected errors (DB down, API timeout, etc.)
    #[error("Internal server error")]
    Internal(#[from] anyhow::Error),
}

// 3. Axum integration via IntoResponse
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = match &self {
            AppError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AppError::NotFound => StatusCode::NOT_FOUND,
            AppError::Unauthorized => StatusCode::UNAUTHORIZED,
            AppError::Internal(err) => {
                // IMPORTANT: Internal logging only, never send to client!
                tracing::error!(target: "server_error", "Critical error: {err:?}");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        };

        let body = Json(ApiErrorPayload {
            error: self.to_string(),
        });

        (status, body).into_response()
    }
}
```

### Why This Combination?

#### `thiserror` for `AppError`
- ✅ **Ergonomic**: `#[derive(Error)]` reduces boilerplate
- ✅ **HTTP mapping**: Each variant can be mapped to an HTTP status
- ✅ **Type safety**: Compiler enforces handling all error cases

#### `anyhow` for `AppError::Internal`
- ✅ **Error chains**: `.context("...")` creates complete error traces
- ✅ **Flexibility**: Any `anyhow::Error` can be converted via `#[from]`
- ✅ **Security**: Only generic error message to client, details in logs

#### Axum's `IntoResponse`
- ✅ **Clean handlers**: `Result<Json<T>, AppError>` + `?` operator
- ✅ **Centralized**: Logging and JSON serialization in one place
- ✅ **Type-driven**: Axum enforces `IntoResponse` for all handler errors

### Example: Usage in Handler

```rust
pub async fn get_user_handler(
    Path(user_id): Path<Uuid>
) -> Result<Json<UserDto>, AppError> {
    // 1. Domain error (thiserror)
    let user = user_service.find_by_id(user_id)
        .await
        .map_err(|e| match e {
            UserDbError::NotFound => AppError::NotFound,
            UserDbError::InvalidId => AppError::BadRequest("Invalid user ID".into()),
        })?;

    // 2. Internal error with context (anyhow)
    let _external_data = external_api_call()
        .await
        .context("Failed to fetch external weather API")?;
    // Thanks to #[from], `?` automatically converts to AppError::Internal!

    Ok(Json(user.into()))
}
```

## Consequences

### Positive

- ✅ **Security**: No sensitive error details (DB queries, stack traces) leak to clients
- ✅ **Observability**: `tracing::error!` with `{err:?}` logs complete error chains including context
- ✅ **Code readability**: Handlers are free of logging code; `?` operator makes error handling implicit
- ✅ **Consistency**: Uniform JSON format `{ "error": "..." }` for all errors
- ✅ **Type safety**: Rust's type system ensures all errors are handled
- ✅ **Axum integration**: Perfectly leverages Axum's strengths (extractors, `IntoResponse`)

### Negative

- ⚠️ **Error enums grow**: With many domain errors, `AppError` becomes large (Mitigation: modules with own errors that convert to `AppError`)
- ⚠️ **anyhow context leakage**: Developers might put sensitive data in `.context()` (Mitigation: code review guidelines)
- ⚠️ **Client-side error handling**: Frontend must work with generic error messages for 500s (Mitigation: good docs, specific errors for domain cases)

### Mitigation

- **Error modules**: Per domain (e.g., `core::errors::user`) own error enums that convert to `AppError`
- **Code review**: Check that `.context()` doesn't contain sensitive data
- **Testing**: Unit tests for `IntoResponse` implementation (status codes, JSON format)

## Alternatives Considered

### 1. Only `thiserror` (without `anyhow`)

```rust
#[derive(Error)]
pub enum AppError {
    #[error("DB Error: {0}")]
    Database(#[from] sqlx::Error),  // ❌ Leaks DB details!
}
```

- **Pros**: Simpler, no additional dependency
- **Cons**: 
  - DB errors leak to client (security risk)
  - No error chains (context) for debugging
- **Why not**: Security risk too high, poor observability

### 2. Only `anyhow` (without `thiserror`)

```rust
pub type AppError = anyhow::Error;  // ❌ No HTTP mapping possible!
```

- **Pros**: Very simple, excellent error chains
- **Cons**: 
  - No mapping to HTTP status codes possible
  - Client receives no structured errors
- **Why not**: Axum requires typed errors for `IntoResponse`

### 3. `eyre` instead of `anyhow`

- **Pros**: Similar power to `anyhow`, better formatting
- **Cons**: Less widespread, similar functionality
- **Why not**: `anyhow` is more established standard, better Axum integration

### 4. Custom Error Struct (without thiserror/anyhow)

```rust
pub struct AppError {
    status: StatusCode,
    message: String,
    source: Box<dyn Error>,
}
```

- **Pros**: Complete control
- **Cons**: Lots of boilerplate, less ergonomic than `thiserror`
- **Why not**: `thiserror` provides same functionality with less code

## Integration with Architecture

### Hexagonal Architecture Compliance

```
HTTP Request → Axum Handler → Command/Query → Aggregate/Projection
                     ↓                        ↓
              AppError ←────────────────── DomainError
                     ↓
              IntoResponse → JSON Response
```

- **`core`**: Defines domain errors (e.g., `UserError`, `SceneError`)
- **`api`**: Maps domain errors to `AppError` (HTTP status mapping)
- **`infra`**: Uses `anyhow::Context` for technical errors (DB, external APIs)

### Error Flow Example

```rust
// core/domain/user.rs
#[derive(Error, Debug)]
pub enum UserDomainError {
    #[error("User not found")]
    NotFound(Uuid),
    #[error("Email already exists")]
    DuplicateEmail(String),
}

// api/handlers/user.rs
async fn update_user(
    State(service): State<UserService>,
    Json(cmd): Json<UpdateUserCommand>,
) -> Result<Json<UserDto>, AppError> {
    service.update(cmd)
        .await
        .map_err(|e| match e {
            UserDomainError::NotFound(id) => AppError::NotFound,
            UserDomainError::DuplicateEmail(_) => AppError::BadRequest(e.to_string()),
            // DB errors etc. become anyhow::Error → AppError::Internal
        })
}

// infra/repository/user.rs
impl UserRepository for PostgresUserRepo {
    async fn find_by_id(&self, id: Uuid) -> anyhow::Result<User> {
        sqlx::query_as("SELECT ... FROM users WHERE id = $1")
            .bind(id)
            .fetch_one(&self.pool)
            .await
            .context("Failed to fetch user from database")?  // anyhow context!
            .map_err(anyhow::Error::from)
    }
}
```

## Dependencies (Cargo.toml)

```toml
[dependencies]
thiserror = "1.0"
anyhow = "1.0"
axum = "0.7"
serde = { version = "1.0", features = ["derive"] }
tracing = "0.1"
```

## Testing Strategy

### Unit Tests for Error Handling

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_error_into_response() {
        let error = AppError::NotFound;
        let response = error.into_response();
        
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        // Check JSON body...
    }

    #[tokio::test]
    async fn test_handler_returns_not_found() {
        let app = create_test_app();
        
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/users/00000000-0000-0000-0000-000000000000")
                    .body(Body::empty())
                    .unwrap()
            )
            .await
            .unwrap();
        
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }
}
```

### Mutation Testing

```bash
cargo mutants --in-diff  # Only test changed error handling code paths
```

## Notes

- **Version**: `thiserror 1.0+`, `anyhow 1.0+`
- **Logging**: Uses `tracing::error!` with `{err:?}` for complete error chains
- **Security**: Never send `anyhow::Error` details to client (only for `Internal`)
- **Frontend**: Document possible HTTP status codes and JSON format in OpenAPI spec

### Best Practices for Developers

1. **Domain errors**: Always define as `thiserror` variant in domain error enum
2. **Technical errors**: Use `.context("...")` to add debugging information
3. **Handlers**: Always return `Result<T, AppError>`, use `?` operator
4. **Logging**: Don't log in handlers, `IntoResponse` does it centrally

### Resources

- [thiserror Documentation](https://docs.rs/thiserror/latest/thiserror/)
- [anyhow Documentation](https://docs.rs/anyhow/latest/anyhow/)
- [Axum Error Handling](https://docs.rs/axum/latest/axum/response/trait.IntoResponse.html)
- [Rust Error Handling Patterns](https://rust-lang.github.io/packaging/guidelines/errors.html)

---

**Related ADRs**:
- [ADR-005: Use Axum as Web Framework](./ADR-005-use-axum.md)
- [ADR-011: Observability with OpenTelemetry](./ADR-011-observability-with-opentelemetry.md)

**Next Steps**:
- Implement `AppError` in `crates/api`
- Refactor existing handlers to `Result<T, AppError>`
- Add unit tests for `IntoResponse`
- Document error types in OpenAPI spec (via `utoipa`)
