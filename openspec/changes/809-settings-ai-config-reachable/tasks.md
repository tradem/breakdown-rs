<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Tasks: 809-settings-ai-config-reachable

## 1. Design docs (before implementation, AGENTS.md §11)

- [x] 1.1 Update `docs/design/screens/settings.md`: wireframe, component
      table, states and interactions for the always-visible AI entry with its
      reachability states.
- [x] 1.2 Update `docs/design/glossary.md` with the new copy rows
      (`settings.aiConfigChecking`, `settings.aiConfigUnreachable`,
      `aiConfig.backendUnreachableTitle`, `aiConfig.backendUnreachableBody`).
- [x] 1.3 `frontend-flutter/AGENTS.md` §1 records the rule: a configuration
      entry point is never hidden by an unresolved scope; it renders its state.
- [x] 1.4 `scripts/check-design-diagrams.sh` — NOT runnable here (`java` is
      absent in this environment, so every block in the repo fails, not just
      the edited one); the block only gained plain text rows, no new syntax.

## 2. Implementation

- [x] 2.1 Add the four copy keys to the de (template) and en ARB catalogs; run
      `flutter gen-l10n`.
- [x] 2.2 Add `lib/features/ai_import/ai_config/ai_config_reachability.dart`:
      `aiConfigReachabilityProvider` (one-shot `backendHealthProbeProvider`
      call) mapping `BackendHealthReported` → reachable and
      `BackendHealthUnreachable` → unreachable; regenerate with `build_runner`.
- [x] 2.3 Rewrite `_AiConfigEntryTile` in `lib/features/settings/settings_screen.dart`:
      drop the active-block/membership gate, render the checking / reachable /
      unreachable states, expose `settings-ai-config-retry`, keep the push.
- [x] 2.4 Add `isBackendUnreachable(ProblemError)` to
      `ai_config_state.dart` and the `ai-config-backend-unreachable` card to
      `ai_config_screen.dart` (title + body + Retry) ahead of the generic
      discovery-error card.
- [x] 2.5 Bump `pubspec.yaml` to `0.4.0-beta.35+127` and add the Unreleased
      CHANGELOG entry (ADR-033 release mechanics).

## 3. Tests

- [x] 3.1 Replace the three `'hidden …'` widget tests with state-rendering
      tests: cold start (no scope), pending/failed membership, resolved denial
      (entry present, screen renders `ai-config-discovery-forbidden`), and a
      post-reset stale persisted season + block scope driven through the real
      resolution providers.
- [x] 3.2 Reachability tests: probe injected as `BackendHealthUnreachable` →
      unreachable subtitle + working Retry; probe pending → checking subtitle;
      server `transport.connectionError` on discovery →
      `ai-config-backend-unreachable` in the screen.
- [x] 3.3 Goldens: the AI entry in its three reachability states
      ({light,dark} × android) plus the screen's unreachable card
      ({light,dark} × android). The issue's fourth entry state
      ("reachable + denied") does not exist as an entry state under C3a: the
      denial is the server's 403 rendered by the screen
      (`ai-config-discovery-forbidden`, already covered by a widget test) —
      the entry and the screen cannot disagree because the entry makes no
      permission claim.
- [x] 3.4 No wall-clock gating (AGENTS.md §6): probe and membership seams are
      injected; the health delay seam is recorded, never awaited.

## 4. Validation

- [x] 4.1 `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test` (full suite) clean.
