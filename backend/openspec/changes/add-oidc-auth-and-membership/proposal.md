## Why

The backend currently exposes all HTTP endpoints unauthenticated, and `core` has no concept of *who* may perform a command or *who* is a member of a project. As the app moves toward multi-user collaborative use (theaters with costume designers and wardrobe staff working on the same production), we need (1) a way to trust the identity of the caller and (2) a domain model for project-scoped membership and roles. ADR-010 already decides that authentication is externalized via OIDC (Logto first, Zitadel later) and that the backend only validates signed JWTs — this change implements that seam and adds the membership bounded context that authorizes against it.

## What Changes

- Add an Axum middleware in `crates/api` that validates OIDC ID-Tokens (JWT signature against the IdP JWKS, `iss`, `exp`, `aud`), extracts a `CurrentUser { sub, email, ... }` value, and injects it as an Axum extractor available to handlers.
- Add no identity/account lifecycle to `crates/core`: user registration, password, MFA, and SSO remain exclusively in the IdP. `core` only references an opaque `UserId` (the OIDC `sub` claim) as a value type alongside the existing `ProjectId`.
- Add a new Bounded Context `membership` to `crates/core` following the established `aggregate / commands / events / error / ports / views` schema. Aggregate: `ProjectMembership`, scoped per `ProjectId`, holding `{ user_id -> role }`. Commands: `InviteMember`, `AcceptInvitation`, `GrantRole`, `RemoveMember`, `LeaveProject`. Events: `MemberInvited`, `InvitationAccepted`, `RoleGranted`, `MemberRemoved`.
- Add an authorization policy layer in `crates/api` (not in `core`) that, before dispatching a write command, queries the membership projection to decide "may `sub` perform action A on project P?".
- Introduce `UserId` as a shared value type in `crates/core/src/shared.rs` (opaque wrapper around the OIDC `sub` string) and thread it as optional command metadata for audit purposes via `kameo_es` metadata — **not** as a payload field on existing commands unless the domain logic itself depends on the actor.
- Roles are domain-local (not IdP-global), because they are production-scoped. The initial role set (`Kostümbildner*in`, `Garderobier*in`) is modeled as an open `enum` that can be extended; the final role set is pending stakeholder confirmation (see Open Questions in `design.md`).

## Capabilities

### New Capabilities
- `oidc-authentication`: Validation of OIDC ID-Tokens in the API layer, extraction of a `CurrentUser` from the JWT claims, and injection as an Axum extractor. No identity lifecycle, no passwords, no SDK coupling to a specific IdP.
- `project-membership`: Core Bounded Context modeling project-scoped membership and roles via a `ProjectMembership` aggregate (event-sourced per `kameo_es`), including ports, views, and projector.
- `api-authorization`: API-layer authorization policy that consults the membership read model before dispatching write commands and before returning project-scoped read data.

### Modified Capabilities
<!-- None at the spec level. Existing commands/ports are unchanged; threading
     UserId as metadata is an infrastructure/internal detail, not a behavior change. -->

## Impact

- **crates/api**: New middleware + extractor for OIDC, new authorization policy module, handler signatures gain an optional `CurrentUser` parameter where authorization is enforced.
- **crates/core**: New `membership` module mirroring the existing four context layouts; new `UserId` value type in `shared.rs`. No changes to existing aggregates' behavior.
- **crates/infra**: New projector for membership events + new projection table; new membership query/repository adapter; no changes to existing projectors or event-store adapters.
- **Dependencies**: Adds an OIDC/JWT validation crate (e.g. `jsonwebtoken` or `oxide-auth` — to be decided in design). ADR-010 already approves the OIDC approach.
- **Operations**: Dev and prod compose gain an IdP entry (Logto Cloud initially has no local container; local dev may use a mocked JWKS or Logto Cloud). The `security-audit` spec continues to cover dependency scanning.
- **Non-goals / deferred**: `Project` aggregate lifecycle (name, dates, status) is explicitly out of scope — `ProjectId` continues to be an opaque UUID as today, pending the stakeholder-driven `Project` proposal. Account lifecycle (registration, password reset, MFA) stays in the IdP. Final role set pending stakeholder confirmation.
