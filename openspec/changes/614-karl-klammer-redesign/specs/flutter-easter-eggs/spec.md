# flutter-easter-eggs

## MODIFIED Requirements

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
