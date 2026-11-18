<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# flutter-easter-eggs

## ADDED Requirements

### Requirement: Deja-vu Cat Discoverability
The Deja-vu Cat SHALL be observable on at least one surface that is
visible longer than the launch splash: in addition to the splash, the
cat SHALL cross the **Seasons home empty state** (the app's canonical
idle surface) through the same `DejaVuCatOverlay`, and a **Vorschau**
(preview) gallery in the Settings screen SHALL render each egg's figure
regardless of month so every egg stays discoverable and testable
year-round.

#### Scenario: Cat crosses the empty seasons surface in October
- **WHEN** the seasons projection is empty, the `dejaVuCat` egg switch
  is enabled, and the current month is October
- **THEN** the guided empty state renders with the non-interactive cat
  overlay on top (the CTAs stay hittable)

#### Scenario: Cat dormant outside October on the empty surface
- **WHEN** the seasons projection is empty, the `dejaVuCat` egg switch
  is enabled, and the current month is not October
- **THEN** the guided empty state renders without the cat overlay

#### Scenario: Gallery preview is month-independent
- **WHEN** the settings screen renders the Easter-eggs gallery with an
  egg's switch enabled
- **THEN** that egg's preview card renders regardless of the current
  month

#### Scenario: Gallery preview honors the per-egg switch
- **WHEN** an egg's switch is flipped off
- **THEN** that egg's preview card disappears immediately and the other
  egg's preview is unaffected

#### Scenario: Gallery preview honors remove-animations
- **WHEN** the system "remove animations" setting is active
- **THEN** the preview figures render their static pose and no
  animation controller runs

### Requirement: Empty-Surface Visitor Preserves the Egg Gates
The empty-surface cat occurrence SHALL reuse the splash overlay so the
October gate, the per-egg switch and the "remove animations" behavior
are preserved by construction; the cat SHALL stay non-interactive on
every hosting surface (no pointer interception, no layout displacement
of actionable elements).

#### Scenario: Egg switch off disables the visitor too
- **WHEN** the `dejaVuCat` egg switch is disabled and the current month
  is October
- **THEN** neither the splash nor the empty-surface occurrence renders
  the cat
