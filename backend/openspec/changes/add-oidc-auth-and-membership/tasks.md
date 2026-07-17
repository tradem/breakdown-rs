## 1. Shared domain primitives

- [ ] 1.1 Add `UserId` opaque value type to `crates/core/src/shared.rs`, mirroring the existing value types (UUIDv7-independent; wraps the OIDC `sub` string, `#[serde(transparent)]`, derives for `Serialize/Deserialize/ToSchema`).
- [ ] 1.2 Add unit tests for `UserId` construction and serialization parity with the IdP `sub` claim.

## 2. Membership Bounded Context — core domain

- [ ] 2.1 Scaffold `crates/core/src/membership/` with `mod.rs`, `aggregate.rs`, `commands.rs`, `events.rs`, `error.rs`, `ports.rs`, `views.rs`, mirroring the existing four context layouts.
- [ ] 2.2 Define `Role` enum in `membership` with the v1 additive variants `Kostümbildner` and `Garderobier`, with backwards-compatible (additive) deserialization.
- [ ] 2.3 Model `BlockMembership` aggregate state: `{ block_id: BlockId, members: HashMap<UserId, MembershipState> }` where `MembershipState` distinguishes pending invitations from active members.
- [ ] 2.4 Implement `kameo_es::Entity` for `BlockMembership` (category `"membership"`, `ID = BlockId`, `Event = MembershipEvent`, `Metadata` per Decision 6).
- [ ] 2.5 Model and implement `InviteMember` / `MemberInvited` `execute` + `apply` (incl. the re-invite-rejection rule).
- [ ] 2.6 Model and implement `AcceptInvitation` / `InvitationAccepted` `execute` + `apply` (incl. no-pending-invitation rejection).
- [ ] 2.7 Model and implement `GrantRole` / `RoleGranted` `execute` + `apply` (incl. non-member rejection, prior-role replacement).
- [ ] 2.8 Model and implement `RemoveMember` / `MemberRemoved` `execute` + `apply`, plus `LeaveBlock` (self-issued equivalent).
- [ ] 2.9 Define `MembershipError` via `thiserror` covering all rejection paths above.
- [ ] 2.10 Define `MembershipView` and the `MembershipRepository` / `MembershipCommands` port traits, following the existing ports pattern.
- [ ] 2.11 Write unit tests for every command's positive path and each rejection rule (`cargo mutants`-resilient).

## 3. Membership infrastructure

- [ ] 3.1 Add a Postgres migration for the `membership` projection table (`block_id`, `user_id`, `role`, `state`, `joined_at`, primary key `(block_id, user_id)`).
- [ ] 3.2 Implement the membership projector (`crates/infra/src/projectors/membership.rs`) consuming `MembershipEvent`, applying idempotently under redelivery (reuse the established ADR-016 pattern).
- [ ] 3.3 Register the membership projector in the `projectors` module and in `main.rs`'s `PostgresProcessor` supervisor.
- [ ] 3.4 Implement `MembershipRepositoryImpl` (query adapter) in `crates/infra/src/queries/membership.rs`.
- [ ] 3.5 Implement `MembershipCommandsImpl` (event-store write adapter) in `crates/infra/src/event_store/`.
- [ ] 3.6 Wire the new ports into `AppState`/`ProductionPorts`/`Ports` trait in `crates/api/src/state.rs`.

## 4. OIDC authentication — API layer

- [ ] 4.1 Resolve Open Question 4: pick the JWT validation crate (`jsonwebtoken` vs. higher-level OIDC resource-server crate); document the choice in `design.md`.
- [ ] 4.2 Add an Axum middleware that fetches and caches the IdP JWKS, validates JWT signature + `iss` + `aud` + `exp`, and attaches `CurrentUser { sub: UserId, email: ... }` to request extensions.
- [ ] 4.3 Implement the `CurrentUser` Axum `FromRequestParts` extractor.
- [ ] 4.4 Return HTTP 401 for missing/expired/invalid tokens and HTTP 503 for unrecoverable JWKS fetch failures.
- [ ] 4.5 Add a dev-mode feature flag/env var that injects a fixed dummy `CurrentUser` (never enabled in prod) so unit/integration tests stay deterministic — resolve Open Question 3.
- [ ] 4.6 Configure `OIDC_ISS`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` env vars; document them in `AGENTS.md` §6.
- [ ] 4.7 Add unit tests for each token-validation branch (valid, missing, expired, bad signature, JWKS-failure).

## 5. Authorization policy — API layer (action-scoped, block-scoped)

- [ ] 5.1 Resolve the **active-Block transport**: decide how the request conveys the `BlockId` the caller is currently working in (path segment, header, body field, or UI session scope). Document the choice in `design.md`.
- [ ] 5.2 Implement an authorization policy module in `crates/api` that resolves the active `BlockId` of the request and queries `MembershipRepository` for the caller's active membership in that block.
- [ ] 5.3 Gate write-command endpoints: return HTTP 403 when the caller is not an active member of the active block; else forward the command.
- [ ] 5.4 Gate block-scoped read endpoints: return HTTP 403 for non-members; return data for members.
- [ ] 5.5 Attach the acting `UserId` as `kameo_es` command metadata for audit on routed write commands, leaving command payloads unchanged (Decision 6).
- [ ] 5.6 Provide a runtime feature flag flipping enforcement between "log-only" and "enforce", per the staged migration plan in `design.md`.

## 6. Integration tests

- [ ] 6.1 Extend `crates/integration-tests` fixtures with membership command/event sequences (Tier 1–3 Postgres-only).
- [ ] 6.2 Add a Tier-4 round-trip test for `membership` command → SierraDB → projector → Postgres read model.
- [ ] 6.3 Add a Tier-4 idempotency-under-redelivery test mirroring the existing redelivery tests.
- [ ] 6.4 Add an API-layer test asserting authorized/non-authorized dispatch (using the dev-mode dummy `CurrentUser`) for at least one write and one read endpoint.

## 7. Architecture & guardrails

- [ ] 7.1 Extend `rust_arkitect` / architecture tests (ADR-017) to assert `crates/core` still has no `sqlx`/`axum`/OIDC-crate dependency after adding `membership` and `UserId`.
- [ ] 7.2 Confirm `cargo deny check bans` and the `security-audit` spec (CI) pass with the new OIDC/validation crate added.
- [ ] 7.3 Confirm `cargo mutants` still scoped to whitebox `#[cfg(test)]` modules; add membership unit tests to the mutation surface.
- [ ] 7.4 Run `./scripts/add-spdx-headers.sh crates/core/src/membership crates/api/src/...` over new files.

## 8. Documentation

- [ ] 8.1 Update `AGENTS.md` §6 with the new env vars and the dev-mode `CurrentUser` toggle.
- [ ] 8.2 Update the OpenAPI `ApiDoc` to include membership endpoints and the `CurrentUser`/401/403 responses.
- [ ] 8.3 Add an ADR (or amendment to ADR-010) recording the JWT-validation-crate decision and the dev-mode auth toggle.

## 9. Open Questions requiring sign-off before implementation

- [ ] 9.0 **Pre-req**: `introduce-season-block-episode-hierarchy` has landed (provides `BlockId` + `Block` aggregate). This change cannot start otherwise.

- [ ] 9.1 Stakeholder: confirm the v1 role set (only `Kostümbildner` + `Garderobier`, or additional roles such as `Regie`, `Maske`, `Produktionsleitung`).
- [ ] 9.2 Stakeholder/product: confirm whether a "theater" maps to a Logto `Organization` containing multiple productions/seasons, and whether cross-theater isolation is required in v1.
- [ ] 9.3 Stakeholder: decide whether audit needs a dedicated queryable audit projection or whether `kameo_es` metadata is sufficient.
- [ ] 9.4 Confirm IdP is Logto Cloud (per ADR-010) at implementation start, or whether the team switches to Zitadel before this change lands.
