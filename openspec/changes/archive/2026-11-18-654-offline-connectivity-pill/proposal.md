<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# 654 — Visible offline-mode pill with battery-friendly connectivity detection

## Why

Issue #654: users get no signal when the device is offline. Read data comes
from the Drift cache (§8: online-first with read-projection cache) and
commands always dispatch over the network and fail with a retry affordance
(§4) — without an offline indicator the stale reads and failing writes look
like app bugs. The app must show a clearly visible pill whenever the device
is offline, transitioning automatically both ways without user interaction.

## What Changes

- **Detection (passive-first, battery-friendly):**
  - Primary source: `connectivity_plus` passive OS signals (Android
    `ConnectivityManager` NetworkCallback) exposed through a seam interface
    (`PassiveConnectivitySource`) so tests push events into controllable
    `StreamController`s — no polling loop anywhere.
  - Secondary confirmation: a single lightweight HTTP probe (bare Dio, no
    auth interceptor, 5 s timeouts) against the configured API base runs
    ONLY when the OS transitions from offline to connected while the app
    believed it was offline. Any HTTP response (even 404) proves
    reachability. Re-probes after failures use exponential backoff
    (15 s base, ×2, capped at 10 min) — no fixed short-interval heartbeat.
  - Captive-portal/dead-route handling: OS says "connected" but the probe
    fails → state `degraded`, pill stays visible; re-probes are backed off
    and canceled (generation counter) when the OS reports offline again —
    no request storms.
- **State (Riverpod, Decision D3):** `@Riverpod(keepAlive: true)`
  `ConnectivityController` exposing `ConnectivityStatus { online, offline,
  degraded }`; the delay/probe/stream seams are `@riverpod` providers so
  tests override them — no wall-clock sleeps in tests (deterministic-tests
  hard rule).
- **UI:** `OfflinePill` in the shell content column below `ShellTopBar`
  (settled decision): visible on all three destinations and every pushed
  route inside the tabs, hidden (animated) when connectivity returns.
  Theme color-scheme roles only (`errorContainer`/`onErrorContainer`),
  `AppSpacing` tokens, semantic live region, localized label.
- **l10n:** `offlinePillLabel` added to `app_de.arb` (template) and
  `app_en.arb` with de/en key parity.

## Impact

- `pubspec.yaml`: `connectivity_plus ^7.3.2` added (passive signal plugin,
  FOSS, no native code of our own).
- New: `lib/src/connectivity/connectivity_providers.dart` (+ codegen
  `connectivity_providers.g.dart`), `lib/features/shell/offline_pill.dart`.
- Modified: `lib/features/shell/app_shell.dart` (pill slot in the content
  column), `lib/l10n/app_{de,en}.arb`.
- Tests: `test/unit/connectivity_controller_test.dart` (state transitions,
  backoff schedule, generation cancellation), `test/features/shell/
  offline_pill_test.dart` (widget test, semantic finders, both branches).
