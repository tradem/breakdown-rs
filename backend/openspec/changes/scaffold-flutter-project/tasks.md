<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Create the project
- [ ] 1.1 `flutter create` Android-first under `frontend-flutter/` (pin min
       SDK, Kotlin, AGP; no macOS target yet)
- [ ] 1.2 Seed `pubspec.yaml` with core deps (Riverpod stack, fpdart,
       secure storage, drift, dio, freezed/json_annotation, dev: build_runner
       / json_serializable / drift_dev / analysis_server_plugin /
       flutter_gherkin)
- [ ] 1.3 `.gitignore` for Flutter build artifacts
- [ ] 1.4 SPDX headers on all seeded `.dart`/`.yaml` files

## 2. Static-analysis config
- [ ] 2.1 `analysis_options.yaml` registering the `analysis_server_plugin`
       package under `analyzer > plugins` and mapping the four rule IDs to
       severities under `analyzer > errors`, per the foundation skills
- [ ] 2.2 `analysis_server_plugin` package skeleton (`breakdown_lints`,
       `lib/main.dart` + top-level `plugin`) with all four rules:
       `discard_result`, `no_throw_in_data_domain`, `no_insecure_tls`, and
       `no_hardcoded_secrets` (each an `AnalysisRule` with a negative test
       fixture)
- [ ] 2.3 `flutter analyze` passes clean on the seeded project
- [ ] 2.4 `flutter analyze` reports the four `breakdown_lints` rules (no
       separate runner) on the seeded project, including the negative
       activation fixtures that assert each rule ID

## Spec-hardening (issue #272) — design resolved

The PR #269 review asked which custom-lint implementation to use (and the
exact rule IDs / wiring). Resolved in `proposal.md` (Design Decisions
D1–D4) and encoded as a requirement in `specs/flutter-scaffold/spec.md`.
Implementation Tasks 2.1–2.4 remain open; the design gap is closed.
- [x] Analyzer-plugin implementation selected (D1: `analysis_server_plugin`
      plugin package `breakdown_lints`; `custom_lint` superseded per issue
      #289 — archived/inactive upstream; enforced via `flutter analyze`,
      not a separate runner)
- [x] Entrypoint defined (D2: top-level `plugin` variable +
      `Plugin.register(PluginRegistry registry)`)
- [x] Exact rule IDs defined (D3: `discard_result`, `no_throw_in_data_domain`,
      `no_insecure_tls`, `no_hardcoded_secrets`; suppression via `// ignore:`)
- [x] `analysis_options.yaml` wiring + CI command defined (D4: `analyzer >
      plugins > analysis_server_plugin` + `analyzer > errors` severities,
      enforced by `flutter analyze`; negative activation tests added)

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
- [x] 4.3 Decide lint-plugin path (issue #289): `custom_lint` is archived and
       explicitly "no longer under active development" upstream; the official
       `analysis_server_plugin` (dart-lang/sdk) is the recommended path. DECISION:
       **migrate to `analysis_server_plugin`**. Updated proposal D1–D4, spec.md,
       AGENTS.md §5/§9, `flutter-ci.yml`, and the `flutter-lint-analysis` skill
       accordingly. The four rule IDs and exit policy are unchanged.
- [ ] 4.4 (carried over, still pending until scaffold lands) Ensure
       `frontend-flutter/AGENTS.md` §5/§9 CI guidance reflects that the
       `breakdown_lints` rules run via `flutter analyze` (analysis server loads
       the `analysis_server_plugin` package) with no separate runner — see the
       D1/D4 updates above. Record this guidance update as part of the scaffold
       landing.
