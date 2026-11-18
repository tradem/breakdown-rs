<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# flutter-easter-eggs

## MODIFIED Requirements

### Requirement: Easter-Eggs Toggle
The general settings section SHALL contain a **per-egg** set of switches
under an "Easter eggs" section header, one switch per registered egg
(`EasterEggId`): "Karl Klammer" and "Deja-vu Cat". Each switch SHALL
default to **enabled** on first launch (no persisted value), SHALL be
persisted on-device under a flat per-egg key, and SHALL be effective
**immediately** — features consume their own egg via a globally reactive
`@riverpod`/`NotifierProvider.family` notifier (`ref.watch`); no app
restart is required and flipping one egg SHALL NOT rebuild the other.

#### Scenario: Default enabled on first launch
- **WHEN** a fresh installation (no persisted value for an egg) opens the
  settings screen.
- **THEN** that egg's switch renders enabled.

#### Scenario: Persistence across restarts
- **WHEN** the user disables one egg's switch and restarts the app.
- **THEN** the persisted value `false` is restored for that egg only —
  the other egg keeps its own value.

#### Scenario: Immediate per-egg effect
- **WHEN** the user flips one egg's switch.
- **THEN** only that egg's `ref.watch`ing consumers update immediately,
  without restart, and the other egg is unaffected.

### Requirement: Result-Typed Persistence Layer
The Easter-eggs persistence layer SHALL be Result-typed (`fpdart`
`Result`), with NO `throw` in `data/`/`domain/`; storage failures are
values (`settings.easter_eggs_read_failed` /
`settings.easter_eggs_write_failed` ProblemDetails-style codes). Each egg
SHALL be persisted under its own flat `shared_preferences` key
(`easter_eggs.karl_klammer`, `easter_eggs.dejavu_cat`) — NOT in
`flutter_secure_storage` (it is not a secret and must not misuse the
secure enclave). On a read failure the fallback SHALL be default ON per
egg plus a **visible error state** in the settings screen — never a silent
failure.

On first launch after the update, the legacy global key `easter_eggs`
SHALL seed every per-egg value that has no stored value, and the legacy
key SHALL then be removed. A failed removal SHALL be non-fatal (the
leftover key is ignored on the next boot); a read failure SHALL fall back
to default ON per egg with the visible error state.

#### Scenario: Read failure falls back visibly
- **WHEN** the underlying preference store fails on read.
- **THEN** every egg falls back to default ON and the settings screen
  surfaces a visible error state per egg — no exception escapes and
  nothing fails silently.

#### Scenario: Legacy flag migrates on first launch after update
- **WHEN** only the legacy `easter_eggs` bool is stored (the pre-update
  install) and the app boots.
- **THEN** that value seeds both per-egg keys and the legacy key is
  removed.

#### Scenario: Migration preserves explicit per-egg choices
- **WHEN** a per-egg key is already stored alongside the legacy key.
- **THEN** the stored per-egg value is kept and only the unset egg is
  seeded from the legacy value.

#### Scenario: Every fallible call asserted
- **WHEN** a test covers the store.
- **THEN** both `Ok` and `Err` branches are asserted (Err-branch rule).

### Requirement: Karl Klammer Assistant in the AI Import View
The AI Import screens (`lib/features/ai_import/`) SHALL host the **Karl
Klammer** Easter egg — an animated clothes-hanger character (Clippy's
behavior re-imagined on a body modeled after the app icon's `checkroom`
hanger glyph; self-drawn, no copied original Clippy material). The figure
SHALL be drawn as a **filled comic-vector silhouette** (hook, head,
shoulders, bottom bar, and lower triangle) so it reads at the 72 px
logical box and below, and SHALL carry a clearly visible expressive face:
large eyes with sclera and pupils, eyebrows, and pose-specific mouths.
Every color SHALL come from the ambient Material 3 color-scheme roles — no
hardcoded color literals. The figure SHALL blink periodically and SHALL
show idle body motion, each pose SHALL have a distinct motion signature,
and all motion SHALL be derived from a single injected animation phase
(deterministic; no wall clock, no randomness). It SHALL be visible ONLY
while **its own** egg flag (`EasterEggId.karlKlammer`) is enabled; when
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

#### Scenario: Hidden when its egg is disabled
- **WHEN** the Karl Klammer egg flag is off and the user opens an AI
  Import screen (or toggles it off while an AI Import screen is open).
- **THEN** no Karl Klammer element, placeholder, or skeleton is visible;
  a running tip/animation is cancelled.

#### Scenario: Independent of the Deja-vu Cat egg
- **WHEN** the Deja-vu Cat egg is disabled while Karl Klammer's is on.
- **THEN** the Karl Klammer assistant still renders in the AI Import view
  (per-egg independence).

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

## ADDED Requirements

### Requirement: Deja-vu Cat Splash Egg (October-only)
The launch splash (`SplashView`) SHALL host the **Deja-vu Cat** Easter
egg: an original, self-drawn black cat (code-drawn `CustomPainter`, no
binary assets, no Matrix film assets or titles) that walks across the
splash content area while the splash is visible. The egg SHALL be visible
ONLY when **both** the `EasterEggId.dejaVuCat` flag is enabled AND the
current month is October, evaluated by a pure gate
(`dejaVuCatActive(enabled:, now:)`, injectable clock — no wall-clock
month logic buried in a widget). Outside October it SHALL be dormant even
when switched on (and SHALL return the next October). The walk SHALL
**loop** continuously while the splash is up — the session-restore
duration SHALL NOT be artificially stretched — and SHALL include a subtle
"déjà vu" pause/glance beat expressed purely in animation. The cat SHALL
walk along the lower band and SHALL NOT cover the brand icon, wordmark, or
spinner. It SHALL be non-interactive (`IgnorePointer`), make no network
calls and no user-level event tracking, and SHALL honor the system
"remove animations" setting by rendering a static pose with no running
controller. All colors SHALL come from the ambient Material 3
color-scheme roles (no hardcoded color literals); the cat's motion SHALL
be derived from a single injected animation phase (deterministic; no wall
clock, no randomness).

#### Scenario: Visible in October when enabled
- **WHEN** the Deja-vu Cat flag is enabled and the gate is evaluated with
  a date in October while the splash is visible.
- **THEN** the cat renders on the splash.

#### Scenario: Dormant outside October even when enabled
- **WHEN** the Deja-vu Cat flag is enabled and the gate is evaluated with
  a date in September or November.
- **THEN** no cat renders — the egg is dormant.

#### Scenario: Hidden when the flag is off
- **WHEN** the Deja-vu Cat flag is disabled (any month).
- **THEN** no cat element, placeholder, or skeleton is visible on the
  splash.

#### Scenario: Looping walk, no artificial extension
- **WHEN** the session restore takes longer than one walk cycle.
- **THEN** the walk loops from the start; the restore is never delayed or
  stretched to fit the animation.

#### Scenario: Déjà-vu pause/glance beat
- **WHEN** the walk reaches the mid-cycle beat.
- **THEN** the cat pauses and glances back before continuing — expressed
  purely in the injected animation phase.

#### Scenario: Remove-animations honored
- **WHEN** the system accessibility setting "remove animations" is
  active.
- **THEN** the cat renders a static pose and no animation controller runs.

#### Scenario: Deterministic gate and motion
- **WHEN** widget/unit tests drive the gate and the walk.
- **THEN** both are pure functions of the injected clock / controller
  phase — no `Future.delayed` wall clock, no randomness.

#### Scenario: Non-interactive
- **WHEN** the cat is visible on the splash.
- **THEN** it never intercepts pointer events (the splash owns no
  interaction) and makes no network call.
