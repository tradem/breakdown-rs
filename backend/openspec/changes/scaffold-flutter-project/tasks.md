<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Create the project
- [ ] 1.1 `flutter create` Android-first under `frontend-flutter/` (pin min
       SDK, Kotlin, AGP; no macOS target yet)
- [ ] 1.2 Seed `pubspec.yaml` with core deps (Riverpod stack, fpdart,
       secure storage, drift, dio, freezed/json_annotation, dev: build_runner
       / json_serializable / drift_dev / custom_lint / flutter_gherkin)
- [ ] 1.3 `.gitignore` for Flutter build artifacts
- [ ] 1.4 SPDX headers on all seeded `.dart`/`.yaml` files

## 2. Static-analysis config
- [ ] 2.1 `analysis_options.yaml` enabling custom lints referenced by the
       foundation skills
- [ ] 2.2 `custom_lint` package skeleton with: `discard-result` analog,
       no-throw-in-`data/domain`, no-hardcoded-secrets heuristics
- [ ] 2.3 `flutter analyze` passes clean on the seeded project

## Spec-hardening (issue #272) — design resolved
The PR #269 review asked which custom-lint implementation to use (and the
exact rule IDs / wiring). Resolved in `proposal.md` (Design Decisions
D1–D4) and encoded as a requirement in `specs/flutter-scaffold/spec.md`.
Implementation Tasks 2.1–2.3 remain open; the design gap is closed.
- [x] Custom-lint implementation selected (D1: `custom_lint` +
      `custom_lint_builder` plugin package; legacy `analysis_server_plugin`
      rejected; `flutter analyze` runs the rules once registered)
- [x] Entrypoint defined (D2: `BreakdownLints extends PluginBase`
      `getLints()`)
- [x] Exact rule IDs defined (D3: `discard_result`, `no_throw_in_data_domain`,
      `no_insecure_tls`, `no_hardcoded_secrets`)
- [x] `analysis_options.yaml` wiring + CI command defined (D4: `analyzer >
      plugins > custom_lint` + `custom_lint: rules:`, enforced by
      `flutter analyze`)

## 3. Composition root & flavors
- [ ] 3.1 `lib/main.dart`: `ProviderScope`, flavor wiring
- [ ] 3.2 Pinned-CA `HttpClient`/`dio` config sourced from `--dart-define`
       (no disable-verification switch)
- [ ] 3.3 Flavors `dev` and `prod` only; `dev` points at localhost backend +
       optional Logto, `prod` at the deployed edge
- [ ] 3.4 Dev auth mode parity with backend: permissive mode only when
       `OIDC_ISS` is absent **and** `DEV_AUTH_SUB` is set (never when OIDC is
       partially configured); impossible in `prod` flavor

## 4. Repo hygiene
- [ ] 4.1 Extend `scripts/add-spdx-headers.sh` to cover `frontend-flutter/`
- [ ] 4.2 First `dart format` + `flutter analyze` pass in CI (advisory until
       `add-flutter-ci-tests` lands coverage gate)
