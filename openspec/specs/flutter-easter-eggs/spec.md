<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-easter-eggs Specification

## Purpose
TBD - created by archiving change 640-dejavu-cat-discoverable. Update Purpose after archive.
## Requirements
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

### Requirement: Easter-Eggs Toggle
The general settings section SHALL contain a `SwitchListTile`
"Easter-Eggs" with an explanatory subtitle (that little surprises in
the app can be switched on or off). The toggle SHALL default to
**enabled** on first launch (no persisted value), SHALL be persisted
on-device, and SHALL be effective **immediately** — features consume it
via a globally reactive `@riverpod` notifier (`ref.watch`); no app
restart is required.

#### Scenario: Default enabled on first launch
- **WHEN** a fresh installation (no persisted value) opens the settings
  screen.
- **THEN** the Easter-eggs switch renders enabled.

#### Scenario: Persistence across restarts
- **WHEN** the user disables the toggle and restarts the app.
- **THEN** the persisted value `false` is restored — the switch renders
  disabled.

#### Scenario: Immediate global effect
- **WHEN** the user flips the toggle.
- **THEN** every `ref.watch`ing consumer (including the Karl Klammer
  overlay in the AI Import view) updates immediately, without restart.

### Requirement: Result-Typed Persistence Layer
The Easter-eggs persistence layer SHALL be Result-typed (`fpdart`
`Result`), with NO `throw` in `data/`/`domain/`; storage failures are
values (`settings.easter_eggs_read_failed` /
`settings.easter_eggs_write_failed` ProblemDetails-style codes). On a
read failure the fallback SHALL be default ON plus a **visible error
state** in the settings screen — never a silent failure. The flag SHALL
be persisted in `shared_preferences`, NOT in `flutter_secure_storage`
(it is not a secret and must not misuse the secure enclave).

#### Scenario: Read failure falls back visibly
- **WHEN** the underlying preference store fails on read.
- **THEN** the notifier falls back to default ON and the settings
  screen surfaces a visible error state — no exception escapes and
  nothing fails silently.

#### Scenario: Every fallible call asserted
- **WHEN** a test covers the store.
- **THEN** both `Ok` and `Err` branches are asserted (Err-branch rule).

### Requirement: Karl Klammer Assistant in the AI Import View
The AI Import screens (`lib/features/ai_import/`) SHALL host a single
Easter egg: the **Karl Klammer** assistant — an animated clothes-hanger
character (Clippy's behavior re-imagined on a body modeled after the app
icon's `checkroom` hanger glyph; self-drawn, no copied original Clippy
material). The figure SHALL be drawn as a **filled comic-vector
silhouette** (hook, head, shoulders, bottom bar, and lower triangle) so it
reads at the 72 px logical box and below, and SHALL carry a clearly visible
expressive face: large eyes with sclera and pupils, eyebrows, and
pose-specific mouths. Every color SHALL come from the ambient Material 3
color-scheme roles — no hardcoded color literals. The figure SHALL blink
periodically and SHALL show idle body motion, each pose SHALL have a
distinct motion signature, and all motion SHALL be derived from a single
injected animation phase (deterministic; no wall clock, no randomness).
It SHALL be visible ONLY while the Easter-eggs toggle is enabled; when
toggled off it SHALL disappear immediately without residue (running
tips/animations cancelled; no skeletons or placeholders). It SHALL be
**non-modal** (never covers primary CTAs, never blocks interaction, always
dismissible by tap), SHALL react contextually to the import-flow states
(no config / queued / running / error / success / idle) with tips and
poses, SHALL use deterministic triggers only (injectable clock /
`StreamController`, never wall-clock or random), SHALL make no network
calls and no user-level event tracking, and SHALL be accessible: tagged
decorative/dismissible for screen readers and honoring the system "remove
animations" setting (static posed figure with all expressions visible,
instead of animation).

#### Scenario: Hidden when Easter eggs disabled
- **WHEN** the Easter-eggs toggle is off and the user opens an AI Import
  screen (or toggles it off while an AI Import screen is open).
- **THEN** no Karl Klammer element, placeholder, or skeleton is visible;
  a running tip/animation is cancelled.

#### Scenario: Contextual reaction to import state
- **WHEN** the import flow reaches a trigger state (e.g. no AI config
  present, a job queued but not yet running, or job error).
- **THEN** the assistant shows the corresponding tip/pose for that state
  (e.g. the "writing a letter…" allusion offering the AI-config entry / a
  thinking pose while queued / a drooping, consoling pose) — and nothing
  else fires.

#### Scenario: Expressive comic-vector figure
- **WHEN** the figure is rendered at the default 72 px size in either
  theme.
- **THEN** it shows a filled hanger silhouette with clearly visible eyes
  (sclera + pupils), eyebrows, and the mouth for the current pose, using
  only Material 3 color-scheme roles.

#### Scenario: Deterministic blink and idle motion
- **WHEN** widget tests drive the figure with `animate: true`.
- **THEN** the blink and body motion are pure functions of the injected
  controller phase (no `Future.delayed` wall clock, no randomness), so
  pumping a fixed duration yields a reproducible frame.

#### Scenario: Non-modal and dismissible
- **WHEN** the assistant is visible over an AI Import screen.
- **THEN** all primary CTAs remain visible and hit-testable (golden +
  widget test), and a tap on the assistant dismisses it for the session.

#### Scenario: Deterministic triggers
- **WHEN** widget tests drive the trigger logic.
- **THEN** timing comes from an injected fake clock /
  `StreamController` — no `Future.delayed` with real wall-clock, no
  randomness.

#### Scenario: Remove-animations honored
- **WHEN** the system accessibility setting "remove animations" is
  active.
- **THEN** the character renders a static pose (all expressions visible)
  instead of animating and no animation controller runs.

#### Scenario: Screen-reader semantics
- **WHEN** a screen reader traverses the AI Import screen.
- **THEN** the assistant is exposed as decorative/dismissible (no
  forced reading order disruption, no blocking focus trap).

