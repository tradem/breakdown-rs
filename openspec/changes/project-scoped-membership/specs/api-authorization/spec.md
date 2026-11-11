<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# api-authorization Delta (project-scoped-membership)

## ADDED Requirements

### Requirement: Season-scoped checks resolve block membership first, then a project-scoped grant

Every season-scoped authorization check that accepts the costume-department
roles SHALL resolve the caller's effective role as: an active block membership
in a block of that season, else an active project-scoped costume role on the
season's `project_id`, else deny. Resolution SHALL live in one
`MembershipRepository` method (`effective_costume_role_in_season`); handlers
and policies SHALL NOT re-implement the precedence.

The check SHALL fail closed: a projection miss, a repository error or an
unresolvable `project_id` SHALL deny, never allow.

#### Scenario: A project-scoped costume role authorizes a block-less season
- **WHEN** a caller holds an active project-scoped `costume_designer` grant on
  the season's project and the season has no blocks
- **THEN** a season-scoped costume-dept check on that season SHALL allow

#### Scenario: A caller with no role in either scope is denied
- **WHEN** the caller holds neither a block membership in the season nor a
  project-scoped costume role on its project
- **THEN** the check SHALL deny and the write SHALL answer `403` with the
  existing problem code (`ai-import.forbidden` for the import upload)

#### Scenario: A projection miss does not widen access
- **WHEN** the project-scoped projection has no row for the caller
- **THEN** the check SHALL deny (unchanged pre-change behavior for callers
  without a project grant)

### Requirement: The report-archive check does not gain the project fallback

`has_active_report_archive_role_in_season` SHALL keep its block-only resolution
and its narrower two-role allowlist (`costume_designer`,
`wardrobe_supervisor`). Manual archive remediation SHALL NOT become reachable
through a project-scoped grant.

#### Scenario: A project-scoped role cannot archive a report manually
- **WHEN** a caller holds only a project-scoped `costume_designer` grant and
  attempts a manual report archive in a season with no block
- **THEN** the check SHALL deny
