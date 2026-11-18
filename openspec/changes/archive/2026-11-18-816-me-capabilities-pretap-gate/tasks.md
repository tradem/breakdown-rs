<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks: 816-me-capabilities-pretap-gate

## 1. Backend — the wire route

- [x] 1.1 `crates/api/src/me.rs`: `MyCapabilitiesResponse` (`has_active_credential_role`,
      `has_active_ops_role`) + `get_my_capabilities<P: Ports>` resolving both through
      `AppState::authorization_policy` (`authorize_credential_role` / `authorize_ops`),
      `// AUTHZ-GATE:` comment stating it REPORTS instead of enforcing.
- [x] 1.2 Mount `GET /me/capabilities` in `crates/api/src/handlers/mod.rs`; register in
      `crates/api/src/lib.rs` (`pub mod me;` + `paths(...)`).
- [x] 1.3 `requirement_for`: narrow equality arm `/me/capabilities` ⇒ `Authenticated`
      (no `/me` prefix wildcard — a future `/me/*` route must be classified explicitly).
- [x] 1.4 Tests: `handler_me_capabilities.rs` (granted / none / ops-only via the
      `OPS_ADMIN_SUBS` allowlist / predicate failure ⇒ server error, never `false`) wired
      into the `handlers` harness; `handler_authz.rs` (401 without token, 200 without
      block membership); `route_coverage.rs` (113 paths + table row);
      `authorization_test.rs` allowlist.
- [x] 1.5 Regenerate `backend/openapi.yaml`; `api` MINOR bump + CHANGELOG.

## 2. Client — regenerate, then gate

- [x] 2.1 `scripts/regen-client.sh` (`CLIENT_VERSION` 1.4.0 → 1.5.0); no hand edits under
      `vendor/breakdown_api/`.
- [x] 2.2 `lib/data/capabilities_repository.dart` + `lib/auth/capabilities.dart`
      (`myCapabilitiesProvider`, one-shot, never throws — the `Result` is unwrapped into
      `AsyncError` at the provider, so "unknown" stays distinguishable from "denied").
- [x] 2.3 `settings_screen.dart`: resolved-denial subtitle `settings.aiConfigDenied`
      ("Keine Berechtigung"); state ranking denied > unreachable > checking > ordinary;
      the tile stays tappable (state, not absence).
- [x] 2.4 `ai_config_controller.dart::aiConfigDiscovery` short-circuits on a resolved
      denial: no `GET /v1/ai-import/config`. Unknown/error proceeds (server authoritative).
- [x] 2.5 `ai_config_state.dart`: client code `ai_config.capability_denied` →
      `aiConfigErrorAdmin`, member of `isAiConfigAuthzDenied` (same card, no retry).
- [x] 2.6 ARB de/en + `flutter gen-l10n`; `build_runner` for the new `.g.dart` files.

## 3. Tests & docs

- [x] 3.1 `test/features/settings/settings_screen_test.dart`: granted / denied / pending /
      error, fetch seam injected; the denied case asserts the retry affordance is absent.
- [x] 3.2 AI-config widget tests: a resolved denial dispatches zero discovery calls and
      renders the administrator narrative.
- [x] 3.3 `docs/design/screens/settings.md` (component table, states, interactions, tests)
      and `docs/design/glossary.md` (copy row) first, then `frontend-flutter/AGENTS.md` §1.
