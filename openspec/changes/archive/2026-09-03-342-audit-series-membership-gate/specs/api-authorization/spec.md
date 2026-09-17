<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->

# api-authorization Specification (delta)

## ADDED Requirements

### Requirement: Series-scoped audit journal is gated by series membership
`GET /v1/audit` SHALL be classified `Requirement::Authenticated` by
`requirement_for()` — the middleware's `X-Active-Block` membership check
SHALL NOT be applied to it — and the handler SHALL verify
`MembershipRepository::has_active_membership_in_series(series_id, actor)`
inside its own body, rejecting the request with HTTP 403 when the caller
holds no *active* membership in any block of the queried series. The check
SHALL be marked with an `// AUTHZ-GATE:` comment and SHALL fail closed: a
repository error denies.

The predicate SHALL be role-agnostic — any active membership in the series
grants access, because the journal is an operational record of the whole
production rather than a costume-department artefact.

#### Scenario: Active member of the series reads the journal
- **WHEN** an authenticated `CurrentUser` with an active membership in a block of `S` requests `GET /v1/audit?series_id=S`
- **THEN** the API layer SHALL return the audit entries of `S`

#### Scenario: Member of an unrelated block is denied
- **WHEN** an authenticated `CurrentUser` whose only active membership is in a block of another series requests `GET /v1/audit?series_id=S`
- **THEN** the API layer SHALL reject the request with HTTP 403 and SHALL NOT query the journal

#### Scenario: Membership lookup fails
- **WHEN** the membership read model returns an error for `GET /v1/audit?series_id=S`
- **THEN** the API layer SHALL reject the request with HTTP 403 (fail closed)

## MODIFIED Requirements

### Requirement: Tenancy boundary is per `SeriesId`, deferred (no v1 enforcement)
The system defines its tenant boundary as **per `SeriesId`** (a production
today; a future "movie" iteration is also a `Series`). In v1 the deployment
is effectively single-tenant and the system SHALL NOT enforce cross-tenant
isolation at the domain layer; the IdP organization check remains upstream at
login (ADR-010). The authorization design SHALL leave an explicit,
documented seam (a future active-series scope + policy check) so that
per-`SeriesId` isolation can be added as an additive follow-up change
without a rewrite.

**Exception (issue #342):** where a route exposes data explicitly selected by
a `series_id` **query parameter** — today `GET /v1/audit` — the tenant
dimension is part of the request rather than of the caller's block scope. For
such routes the system SHALL verify active membership in the queried series
in the handler (`MembershipRepository::has_active_membership_in_series`) and
SHALL NOT rely on the active-`BlockId` membership check, which would give
false assurance. This is the seam above, activated for one route; it does not
introduce general per-`SeriesId` isolation.

#### Scenario: Single-tenant v1 is allowed
- **WHEN** a request is authorized in a v1 single-tenant deployment
- **THEN** the policy SHALL decide based on the active `BlockId` membership only, with no cross-tenant check

#### Scenario: A series-selected route checks the queried series
- **WHEN** a request selects data by `series_id` query parameter
- **THEN** the API layer SHALL verify the caller's active membership in that series and SHALL reject with HTTP 403 on denial
