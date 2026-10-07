<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Series-level costume-photo authorization (issue #535)

## Why

Costume-photo authorization hangs off a **season-typed** predicate
(`MembershipRepository::has_active_costume_role_in_season`), so `SeasonId` is
burned into the security layer. For film/theatre productions a `SeasonId` is not
a sensible container, and a costume is shared across seasons (m:n repertoire,
#453/#534). ADR-035 **B2/S2** mandates the authorization level, not a
production-form-specific container, and #535 is the S2 enforcement change.

## Decisions (resolved with the issue author)

1. **Wire shape of the client-gate signal — new endpoint.** The client mirror
   needs a series-level signal; `GET /series/{id}/membership` mirrors
   `GET /seasons/{id}/membership` one level up, with a dedicated
   `SeriesMembershipDto` (one scope per resource, no dual-scoped DTO body).
   `derive_capabilities` semantics carry over unchanged.
2. **Unresolvable container → 422 `costume.container-unresolved`** (registered
   `problem_codes!` entry + Fluent text in `de`/`en`). Keeps the existing 422
   semantics of `authorize_costume_scoped`'s empty-scope case, switches the
   ad-hoc validation string to a stable code clients branch on.
3. **Photo path only.** The three photo handlers
   (`upload_costume_photo`, `get_costume_photo_bytes`, `delete_costume_photo`)
   migrate to the series predicate; the other `authorize_costume_scoped`
   consumers (detail routes, `set_costume_category`, repertoire add/remove on
   the **target** season) keep their season-scoped gates — their invariants
   are genuinely season-scoped (category season-match, archive terminality).
4. **Client mirror (frontend-flutter AGENTS §5 hard rule):** the photo gate
   (`checkPhotoCapability` callsites) resolves the series and checks the
   backend-computed `has_active_costume_role_in_series` before any network
   call; Err-branches stay `membership.pending` (never deny-by-absence).
5. **No new `*_in_season` predicate** (ADR-035 B2) — the new predicate is
   series-typed and the S2 change *removes* the season-typed call from the
   photo path.

## What changes

- **core:** `MembershipRepository::has_active_costume_role_in_series`; problem
  code `COSTUME_CONTAINER_UNRESOLVED` in `error_registry.rs` (+ count update).
- **infra:** SQL impl (membership ⋈ block on `series_id`, costume-role role
  set, active) mirroring `has_active_membership_in_series`.
- **api:** `GET /series/{id}/membership` (`SeriesMembershipDto`);
  `authorize_costume_in_series` gate helper (strict
  `series_id_for_costume` resolution at the API edge — the only legitimate
  read-model consumer: resolution is REQUIRED for photo authorization, a
  lookup failure is a 500, and only a costume with neither character nor
  repertoire answers 422 `costume.container-unresolved`; the best-effort
  audit-metadata rule does NOT apply to this authorization lookup); the
  three photo handlers migrate; `openapi.yaml`
  regenerated; route-coverage inventory updated.
- **infra integration tests:** Tier-4 predicate round-trip in
  `membership_round_trip.rs` (same-series different-season allow, foreign
  series deny, pending/removed deny).
- **api handler tests:** deliberate broadening regression (role in season B →
  photo ops in season A of the same series → 2xx), negative 403 for a foreign
  series, 422 `costume.container-unresolved`, series-membership handler,
  Err-branch 500 surface (issue #537 semantics).
- **security doc:** `docs/security/security-architecture.md` gains the new
  predicate + role set, the documented scope-widening rationale, and the
  relationship to the role-agnostic `has_active_membership_in_series`.
- **frontend-flutter:** `vendor/breakdown_api` regenerated
  (`scripts/regen-client.sh`); series membership fetch (dev-auth mode
  short-circuit included); photo gate mirrors the series predicate; widget
  tests + goldens for allow/deny/pending.

## Scope boundaries

- The repertoire stays the costume's **domain** scope (list membership,
  series resolution, reports); only the photo **authorization** level moves up
  (ADR-035 S2 enforcement paragraph).
- #533/#534 prerequisites are closed (2026-09); multi-season resolution relies
  on the #534 repertoire state.
- No schema churn (B5): `SeriesId` spelling stays; the rename is #591.
