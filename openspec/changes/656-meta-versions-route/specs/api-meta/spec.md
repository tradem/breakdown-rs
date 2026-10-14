<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Delta Spec: api-meta (issue #656)

## ADDED Requirements

### Requirement: Meta versions endpoint

The system SHALL expose `GET /v1/meta/versions` returning the compile-time
versions of the workspace crates meaningful to clients (`api`, `core`,
`infra`), sourced exclusively from `CARGO_PKG_VERSION` compile-time
constants — no runtime file reads, no manifest parsing.

#### Scenario: Authenticated client fetches crate versions

- **WHEN** a request with a valid OIDC token hits `GET /v1/meta/versions`
- **THEN** the API answers `200 application/json` with an object carrying
  the `api`, `core` and `infra` version strings, matching
  `backend/openapi.yaml`.

#### Scenario: Unauthenticated request is rejected

- **WHEN** a request without a valid OIDC token hits `GET /v1/meta/versions`
- **THEN** the API answers `401` (the route is `Authenticated`, not
  `Public` — decided in the change proposal to avoid anonymous version
  fingerprinting).

#### Scenario: Versions are compile-time constants

- **WHEN** the API binary is built
- **THEN** the reported versions equal each crate's `CARGO_PKG_VERSION` at
  build time; the handler performs no I/O.
