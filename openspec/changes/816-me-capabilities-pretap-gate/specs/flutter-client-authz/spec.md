<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-client-authz

## ADDED Requirements

### Requirement: Exact Pre-Tap Credential Gate From the Global Capability Route

A client-side AUTHZ-GATE mirror for a **deployment-scoped** backend predicate
SHALL read that predicate from the wire (`GET /v1/me/capabilities`) instead of
approximating it from a season-scoped membership signal. The Settings
AI-configuration entry SHALL render a resolved denial as "Keine Berechtigung"
in its subtitle (a state, never a hidden entry), and a resolved denial SHALL
suppress the AI-configuration discovery dispatch: no `GET /v1/ai-import/config`
request SHALL be issued. An unresolved capability answer (probe in flight,
transport failure, server error) SHALL NOT be treated as a denial — the request
proceeds and the server stays authoritative.

#### Scenario: Resolved denial before the tap

- **WHEN** the capability route answers `has_active_credential_role: false`
- **THEN** the entry's subtitle reads "Keine Berechtigung", the entry stays
  tappable, and pushing the screen dispatches **zero** discovery requests — the
  screen renders the administrator narrative from the client-detected code
  `ai_config.capability_denied`, with no retry affordance.

#### Scenario: Granted capability

- **WHEN** the capability route answers `has_active_credential_role: true`
- **THEN** the entry renders its ordinary subtitle and the screen performs its
  normal discovery (the server remains the authority on every call).

#### Scenario: Unknown is not a denial

- **WHEN** the capability probe is still in flight, failed at the transport
  level, or answered 5xx
- **THEN** the entry renders "Zugriff wird geprüft…" / the reachability state,
  and the AI-configuration discovery still runs — an unknown capability is
  never rendered as "Keine Berechtigung".

#### Scenario: A season-scoped signal is not reused for a deployment-scoped gate

- **WHEN** a PR pre-gates a credential-scoped surface on a season-scoped
  membership predicate (the #809-era superset that also admits
  `wardrobe_supervisor` and reads a stale scope as a denial)
- **THEN** review rejects it: the global capability route is the only permitted
  source, and ADR-035 B2 forbids adding a new season-scoped predicate for it.
