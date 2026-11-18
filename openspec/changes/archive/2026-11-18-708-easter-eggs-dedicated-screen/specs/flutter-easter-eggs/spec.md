<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->

# flutter-easter-eggs

## MODIFIED Requirements

### Requirement: Easter-Eggs Toggle
The settings screen's general section SHALL contain a single
**Easter-eggs entry tile** (leading icon, title + subtitle, chevron)
that pushes the dedicated **Easter-eggs screen** (issue #708 — the
counter-model of the AI-configuration entry, issue #643). The dedicated
screen SHALL contain the **per-egg** set of switches under an
"Easter eggs" section header, one switch per registered egg
(`EasterEggId`): "Karl Kleiderbügel" and "Deja-vu Cat". Each switch
SHALL default to **enabled** on first launch (no persisted value), SHALL
be persisted on-device under a flat per-egg key, and SHALL be effective
**immediately** — features consume their own egg via a globally reactive
`@riverpod`/`NotifierProvider.family` notifier (`ref.watch`); no app
restart is required and flipping one egg SHALL NOT rebuild the other.
The entry tile dispatches no command and reads no network resource, so
it carries NO membership gate (contrast the AI-configuration entry).

#### Scenario: Settings keep only the entry tile
- **WHEN** the settings screen renders.
- **THEN** the general section shows exactly one Easter-eggs affordance
  — the entry tile — and no per-egg switch or gallery preview is
  rendered inline.

#### Scenario: Entry tile pushes the dedicated screen
- **WHEN** the user taps the Easter-eggs entry tile.
- **THEN** the dedicated Easter-eggs screen pushes on top of the
  settings screen (same navigator stack), with its own app bar and a
  back affordance.

#### Scenario: Entry tile is unconditional
- **WHEN** the settings screen renders in any flavor with or without an
  active-block scope.
- **THEN** the entry tile renders — the per-egg preferences are
  local-only `shared_preferences`, so no membership gate applies.

#### Scenario: Default enabled on first launch
- **WHEN** a fresh installation (no persisted value for an egg) opens
  the Easter-eggs screen.
- **THEN** that egg's switch renders enabled.

#### Scenario: Persistence across restarts
- **WHEN** the user disables one egg's switch and restarts the app.
- **THEN** the persisted value `false` is restored for that egg only —
  the other egg keeps its own value.

#### Scenario: Immediate per-egg effect
- **WHEN** the user flips one egg's switch.
- **THEN** only that egg's `ref.watch`ing consumers update immediately,
  without restart, and the other egg is unaffected.

### Requirement: Deja-vu Cat Discoverability
The Deja-vu Cat SHALL be observable on at least one surface that is
visible longer than the launch splash: in addition to the splash, the
cat SHALL cross the **Seasons home empty state** (the app's canonical
idle surface) through the same `DejaVuCatOverlay`, and a **Vorschau**
(preview) gallery on the **dedicated Easter-eggs screen** (reached from
the settings entry tile, issue #708) SHALL render each egg's figure
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
- **WHEN** the Easter-eggs screen renders the gallery with an egg's
  switch enabled
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
