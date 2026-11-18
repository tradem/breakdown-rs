<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-settings-configuration-reachability

## ADDED Requirements

### Requirement: A Configuration Entry Point Is Never Hidden by an Unresolved Scope

The Settings screen SHALL always render the AI-configuration entry in its AI
section, independent of the sticky active-block scope, the season-scoped
membership resolution, or any persisted scope that no longer resolves. An
unresolved, erroring or stale scope SHALL NOT remove the entry: a
configuration surface hidden by "unknown" is indistinguishable from an absent
one, and it disappears exactly in the cold-start / post-reset / projector-lag
state where the user needs it. The entry's subtitle SHALL state what the
client currently knows instead.

#### Scenario: Cold start without any scope

- **WHEN** the app is cold-started and no active-block scope is set (no season,
  no block)
- **THEN** the AI section renders the AI-configuration entry, tappable, with a
  subtitle stating that access is being checked

#### Scenario: Persisted scope points at data that no longer exists

- **WHEN** the persisted active-season anchor resolves to no season row and the
  persisted per-season block scope names a deleted block (e.g. after a dev data
  reset)
- **THEN** the AI-configuration entry is still rendered and still opens the
  configuration screen without the user first navigating into a season or block

#### Scenario: Membership is pending, failed or denied

- **WHEN** the season-scoped membership fetch is in flight, has failed, or has
  resolved to `hasActiveCostumeRoleInSeason == false`
- **THEN** the entry remains rendered and tappable (the client does not spend
  the ambiguity on hiding the only entry point)

### Requirement: Backend Reachability Is Rendered Before Configuration State

Before claiming anything about the configuration, the AI section SHALL probe
backend reachability through the existing health seam
(`backendHealthProbeProvider`, `GET /v1/health`, public, never throws) as a
**one-shot** probe — no polling, no second probe implementation — and SHALL
render a distinct, non-blocking, localized state when the backend produced no
answer. A failed read SHALL NOT be rendered as "no configuration exists". The
unreachable state SHALL offer an explicit Retry that re-runs the probe, and
SHALL NOT block opening the configuration screen.

#### Scenario: Backend answers

- **WHEN** the one-shot probe reports a healthy, degraded or unhealthy backend
  (the backend answered)
- **THEN** the entry renders its ordinary subtitle and offers the push to the
  configuration screen

#### Scenario: Backend is unreachable

- **WHEN** the one-shot probe yields `BackendHealthUnreachable` (transport
  failure, timeout, unparsable body)
- **THEN** the entry renders the localized unreachable subtitle plus a Retry
  action, makes no "no configuration" claim, and still pushes the
  configuration screen

#### Scenario: Probe still in flight

- **WHEN** the one-shot probe has not answered yet
- **THEN** the entry renders the localized "access is being checked" subtitle
  and remains tappable

### Requirement: A Failed Read Is Not an Absent Configuration on the Screen

Inside the configuration screen, a discovery failure whose stable problem code
reports that no answer was produced at all (`transport.connectionError`,
`transport.connectionTimeout`, `transport.sendTimeout`,
`transport.receiveTimeout`, `transport.unknown`) SHALL render the localized
unreachable state with a Retry, ahead of the generic discovery-error card, and
SHALL NEVER render the first-run form.

#### Scenario: Discovery fails because the backend is down

- **WHEN** `GET /v1/ai-import/config` fails with one of the "no answer"
  transport codes
- **THEN** the screen renders the unreachable card (title, explanatory body,
  Retry) and not the first-run form

#### Scenario: Retry after the backend returns

- **WHEN** the user retries once the backend answers again
- **THEN** discovery re-runs and the resolved state (first-run or configured)
  renders

### Requirement: Denial Stays Server-Authoritative

The client SHALL NOT pre-gate the AI-configuration entry on a client-side role
approximation: the backend gate is the deployment-scoped credential-role
predicate that is not exposed on the wire, and the season-scoped membership the
entry used to read is a superset that made a stale scope look like a denial. A
denial SHALL be rendered from the server's scoped 403 arms
(`ai-config.forbidden`, `settings.forbidden`) inside the configuration screen,
with the localized administrator narrative and WITHOUT a retry affordance.

#### Scenario: User without the credential role

- **WHEN** the backend answers 403 `ai-config.forbidden` (or
  `settings.forbidden`) on discovery
- **THEN** the entry was rendered and reachable, and the screen renders the
  localized administrator narrative without a retry affordance
