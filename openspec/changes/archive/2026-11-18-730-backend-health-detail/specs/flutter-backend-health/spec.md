<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-backend-health Delta

## ADDED Requirements

### Requirement: Backend Health Pill

The account drawer SHALL lead with a backend health pill derived from the
public `GET /v1/health` readiness report, showing the aggregate tier
(`healthy` / `degraded` / `unhealthy` / `offline`) as a Material Symbol, a
DTCG semantic status token color, and a visible localized label — color
SHALL never be the sole carrier of meaning. The pill SHALL stay empty
until the first probe has answered, so it never asserts a tier nobody
measured. // AUTHZ-GATE: no client-side membership check applies —
`/v1/health` is public by backend design and the pill issues no command.

#### Scenario: Pill names the tier

- **WHEN** the first probe answers `Healthy`
- **THEN** the drawer shows the pill with the check icon, the success
  token color, and the localized label "Backend bereit" (never color
  alone), and screen readers announce the label exactly once.

#### Scenario: Empty until measured

- **WHEN** the drawer is opened before the first probe has answered
- **THEN** the pill renders nothing (the slot collapses) instead of
  showing a tier.

### Requirement: Tappable Health Pill

The pill SHALL be a tap target covering its whole surface and SHALL open
the backend health detail sheet. Its semantics node SHALL expose the
BUTTON role, a localized open hint, and the tap action (the child
semantics are excluded to keep the tier announcement single-sourced, so
the wrapper must carry the action itself).

#### Scenario: Tap opens the detail sheet

- **WHEN** the user taps the pill in the open account drawer
- **THEN** the health detail sheet opens as a modal bottom sheet over the
  still-open drawer, and dismissing it returns to that drawer.

#### Scenario: Screen readers can activate the pill

- **WHEN** a screen reader focuses the pill
- **THEN** it announces the tier label, the localized open hint, and the
  button role, and activating it opens the detail sheet.

### Requirement: Backend Health Detail Sheet

The detail sheet SHALL render the probe's per-dependency results: an
aggregate tier row using the pill's vocabulary, then one row per
dependency check with a functional, topology-free localized label, a
localized status word, and the status-token icon. Broken dependencies
SHALL sort first (then degraded, then healthy; wire order preserved
within a bucket). The backend's own `description` text SHALL NOT be
rendered — the client localizes its own copy keyed on the check name and
status — and unknown check keys SHALL fall back to a generic localized
label rather than printing the raw key.

#### Scenario: Broken dependency is named

- **WHEN** the report is `Unhealthy` with `vault` broken and the other
  checks healthy
- **THEN** the sheet shows the aggregate row "Backend gestört" and lists
  "Geheimnisverwaltung — gestört" FIRST, with the other dependencies below
  it, and renders no raw check key nor English server description.

#### Scenario: Offline asserts no dependency state

- **WHEN** the probe produced no usable answer (transport failure,
  timeout, unparsable body) or the device is passively offline
- **THEN** the sheet shows "Backend nicht erreichbar" with the re-check
  explanation and NO dependency rows, because nothing was measured.

#### Scenario: Tier reported without entries

- **WHEN** the backend answers with a tier but an empty `entries` map
- **THEN** the sheet shows the aggregate row plus "Der Server meldet
  keine Details zu den Abhängigkeiten." instead of an empty list.
