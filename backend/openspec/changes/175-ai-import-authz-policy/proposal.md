<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Proposal: Route AI import authorization through `AuthorizationPolicy` (issue #175)

## Problem

The AI import handlers perform handler-internal authorization by calling
`membership_repo()` directly:

- `authorize_ai_block` → `membership_repo().has_active_costume_role_in_season(..)`
- `authorize_ai_job` → same season-scoped call (identical deviation)
- `credential_role_gate`, `list_ai_providers`, `list_ai_models` →
  `membership_repo().has_active_credential_role(..)`

Per the AGENTS.md rule for `Authenticated`-only privileged handlers, these
checks must be routed through the `AuthorizationPolicy` port with an
`// AUTHZ-GATE:` comment at each handler-internal check (CodeRabbit
discussion on PR #169, issue #175).

## Design

### Fallible policy methods (core, additive)

The existing `AuthorizationPolicy` port is **infallible** (errors map to
`Deny`). Issue requirement #4 mandates that repository failures stay
**visible as mapped errors** (currently `.map_err(map_err)?` → 5xx), so the
AI gates need *fallible* policy methods:

```rust
// core::membership::policy::AuthorizationPolicy (new, default Deny)
async fn authorize_season_result(&self, ctx: &SeasonAuthContext)
    -> Result<PolicyDecision, DomainError>;
async fn authorize_credential_role(&self, actor: &UserId)
    -> Result<PolicyDecision, DomainError>;
```

Defaults return `Ok(PolicyDecision::Deny)`, so unrelated policy
implementations are unaffected (additive MINOR on `core`).

### Policy implementations (api)

- `MembershipAuthorizationPolicy` implements both new methods, delegating to
  `has_active_costume_role_in_season` / `has_active_credential_role` and
  propagating `Err` unchanged (failures are *not* conflated with denial).
- `SeasonPhotoAccessPolicy` implements `authorize_season_result` mirroring
  its infallible `authorize_season` (same repo call, but `Err` propagates).

### Composition root wiring (api)

`AppState<P>` gains `pub authorization_policy: Arc<dyn AuthorizationPolicy>`,
constructed in `AppState::new`/`with_ai_import` from
`ports.membership_repo().clone()` (requires `P::MembershipRepo: Clone`, true
for `MembershipRepositoryImpl` and the test fakes). `main.rs` reuses this Arc
for the `AuthorizationState` middleware instead of rebuilding it.

### Handler changes (api)

| Function | New check |
|---|---|
| `authorize_ai_block` | `authorize_season_result(SeasonAuthContext { season_id, action: Write })` |
| `authorize_ai_job` | `authorize_season_result(..)` (action passed by caller) |
| `credential_role_gate` | `authorize_credential_role(&user.sub)` |
| `list_ai_providers` | `authorize_credential_role(&current_user.sub)` |
| `list_ai_models` | `authorize_credential_role(&current_user.sub)` |

Behavior preserved: `403` on `Deny`, `map_err` on `Err`, `// AUTHZ-GATE:`
comments retained (and added at the helper bodies).

## Tests

- **Policy level** (`crates/api/tests/auth_authorization.rs`): allowed /
  denied / repository-error cases for `authorize_season_result` and
  `authorize_credential_role` on `MembershipAuthorizationPolicy` (and the
  `SeasonPhotoAccessPolicy` season-result mirror).
- **Handler level** (new `crates/api/tests/handler_ai_import_authz.rs`):
  `list_ai_providers` / `list_ai_models` return `403` on denial and map
  repository errors (503) while allowing granted callers (200). The shared
  `FakeMembershipRepo` gains a configurable credential-role result.

## Version bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.5.0 | 0.6.0 | MINOR | New additive `AuthorizationPolicy` trait methods (defaults) |
| `api` | 0.4.7 | 0.5.0 | MINOR | New pub `AppState` field; consumes new core policy API |
| `infra` | 0.10.0 | 0.10.0 | none | No infra change |
