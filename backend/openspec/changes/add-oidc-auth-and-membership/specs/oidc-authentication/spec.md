## ADDED Requirements

### Requirement: OIDC ID-Token validation
The API layer SHALL validate every incoming request's OIDC ID-Token by verifying the JWT signature against the configured IdP JWKS, and by checking the `iss`, `aud`, and `exp` claims. Requests without a valid token SHALL be rejected.

#### Scenario: Valid token is accepted
- **WHEN** a request arrives with a `Authorization: Bearer <jwt>` header whose signature verifies against the cached JWKS and whose `iss`, `aud`, and `exp` claims are valid
- **THEN** the middleware SHALL attach a `CurrentUser` value (derived from the token claims, including at minimum `sub` and `email`) to the request extensions and forward the request to the handler

#### Scenario: Missing token is rejected
- **WHEN** a request arrives without an `Authorization` header or with a non-Bearer scheme
- **THEN** the middleware SHALL reject the request with HTTP 401

#### Scenario: Expired token is rejected
- **WHEN** a request arrives with a token whose `exp` claim is in the past
- **THEN** the middleware SHALL reject the request with HTTP 401

#### Scenario: JWKS fetch failure is surfaced as 503
- **WHEN** the middleware cannot reach the IdP JWKS endpoint to verify a token
- **THEN** the middleware SHALL reject the request with HTTP 503, distinguishing a backend/IdP failure from a client authentication failure

### Requirement: CurrentUser extractor availability
The API layer SHALL provide an Axum extractor that resolves to the authenticated `CurrentUser` from request extensions, so that handlers obtain the caller without re-implementing token validation.

#### Scenario: Handler reads the caller
- **WHEN** a handler declares a `CurrentUser` argument
- **THEN** Axum SHALL inject the `CurrentUser` previously attached by the middleware

### Requirement: No IdP-specific SDK coupling
The API layer SHALL depend only on the standard OIDC JWT contract (signed JWT + JWKS) and SHALL NOT depend on any single IdP's SDK. Switching the configured `iss` and JWKS URL SHALL be sufficient to change IdP.

#### Scenario: Switching IdPs is configuration-only
- **WHEN** the operator changes the configured `iss` issuer and JWKS URL from one compliant OIDC provider (e.g. Logto) to another (e.g. Zitadel)
- **THEN** the backend SHALL continue to validate tokens correctly with no code change

### Requirement: Identity lifecycle stays outside the backend
The backend SHALL NOT implement user registration, password handling, MFA, account recovery, or session storage. These concerns SHALL remain exclusively in the configured OIDC IdP.

#### Scenario: Backend only references an opaque subject
- **WHEN** the backend needs to identify a user
- **THEN** it SHALL use the OIDC `sub` claim, wrapped as an opaque `UserId` value type, and SHALL NOT dereference or store identity attributes beyond what is present in the signed token's standard claims
