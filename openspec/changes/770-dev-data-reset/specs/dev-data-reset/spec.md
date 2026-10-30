<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# dev-data-reset

## ADDED Requirements

### Requirement: Dev-only reset without an HTTP surface

The reset tooling SHALL be a local maintenance binary and SHALL NOT be reachable
over HTTP.

#### Scenario: No route exists

- **WHEN** the OpenAPI contract is inspected
- **THEN** it contains no reset/delete-all route
- **AND** the reset engine is only callable from `reset-dev-data`

### Requirement: Prod refusal

The tooling SHALL refuse to run unless the target is an acknowledged local
development stack.

#### Scenario: Non-development stack

- **WHEN** `--env dev` is absent, or `APP_ENV` is not a development value, or
  `REQUIRE_IN_TRANSIT_TLS=true`, or `DATABASE_URL`/`SIERRADB_URL` resolve to a
  non-loopback host
- **THEN** the run aborts before any write and names the failing layer

### Requirement: Plan before write

`--dry-run` SHALL print the complete keep/reset plan for both levels and write
nothing.

#### Scenario: Dry run

- **WHEN** `reset-dev-data --level <imports|business> --dry-run --env dev` runs
- **THEN** every keep/reset category, operational table, bucket and count is
  printed
- **AND** no database row, event or object is modified

### Requirement: Closed keep-list

Every aggregate category SHALL be classified keep or reset, and a new aggregate
SHALL NOT inherit "keep" by default.

#### Scenario: New aggregate without classification

- **WHEN** an aggregate declares a category that is not in the registry
- **THEN** the `dev_reset` suite fails
- **AND** adding the variant without classifying it is a compile error

### Requirement: Import replay without losing configuration

Level `imports` SHALL make a re-upload of a previously imported document produce
a fresh job while keeping `ai_config`, `settings`, `membership` and Vault
untouched.

#### Scenario: Re-upload after reset

- **WHEN** `--level imports` completed
- **THEN** re-uploading the same document answers `202` with a new job id
- **AND** the AI config and credential bindings are unchanged

### Requirement: Business reset replays the configuration

Level `business` SHALL export the keep-list verbatim before wiping and replay it
afterwards, and SHALL never touch Vault.

#### Scenario: Configuration survives

- **WHEN** `--level business` completed and the API is running
- **THEN** every business projection count is `0`
- **AND** the keep streams hold their exported events and their projections are
  rebuilt
- **AND** `GET /v1/ai-import/config/{id}` still returns the
  provider/model/decision triple

### Requirement: Backup and confirmation by default

A run SHALL take a backup unless `--no-backup` is typed, and SHALL require either
`--yes` or a retyped target before writing.

#### Scenario: Missing confirmation

- **WHEN** the typed confirmation does not equal `<host>/<database>`
- **THEN** nothing is written
