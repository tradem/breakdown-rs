<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Create the project
- [x] 1.1 `flutter create` Android-first under `frontend-flutter/` (pin min
       SDK, Kotlin, AGP; no macOS target yet) — generated via
       `flutter create --platforms=android --project-name frontend_flutter
       --org rs.breakdown` into a temp dir, merged into `frontend-flutter/`
       (AGENTS.md/.pi/openapitools.json/.gitleaks.toml preserved)
- [x] 1.2 Seed `pubspec.yaml` with core deps (Riverpod stack, fpdart,
       secure storage, drift, dio, freezed/json_annotation, dev: build_runner
       / json_serializable / drift_dev / flutter_gherkin) via `flutter pub add`
- [x] 1.3 `.gitignore` for Flutter build artifacts (from `flutter create`)
- [x] 1.4 SPDX headers on all seeded `.dart`/`.yaml` files (added by hand +
       `scripts/add-spdx-headers.sh`)

## 2. Static-analysis config
> **Status:** 2.1 / 2.2 / 2.4 (the `breakdown_lints` analyzer-plugin package
> with the four rules) are implemented in a **follow-up commit** within this
> change — see the `breakdown_lints` package under `frontend-flutter/packages/`.
> Until that lands, `analysis_options.yaml` uses the `flutter_lints` baseline
> and `flutter analyze` is green (Task 2.3).
- [ ] 2.1 `analysis_options.yaml` registering the `breakdown_lints`
       analyzer-plugin package (built on `analysis_server_plugin`) under
       `analyzer > plugins` and mapping the four rule IDs to severities under
       `analyzer > errors`, per the foundation skills — **pending** (next commit)
- [ ] 2.2 `analysis_server_plugin` package skeleton (`breakdown_lints`,
       `lib/main.dart` + top-level `plugin`) with all four rules:
       `discard_result`, `no_throw_in_data_domain`, `no_insecure_tls`, and
       `no_hardcoded_secrets` (each an `AnalysisRule` with a negative test
       fixture) — **pending** (next commit)
- [x] 2.3 `flutter analyze` passes clean on the seeded project
       (`flutter analyze` → *No issues found!*)
- [ ] 2.4 `flutter analyze` reports the four `breakdown_lints` rules (no
       separate runner) on the seeded project, including the negative
       activation fixtures that assert each rule ID — **pending** (next commit)

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
      plugins > breakdown_lints` — the project plugin package, not the
      `analysis_server_plugin` framework dep — + `analyzer > errors`
      severities, enforced by `flutter analyze`; negative activation tests
      assert all four rule IDs)

## 3. Composition root & flavors
- [x] 3.1 `lib/main.dart` → `lib/app.dart` (`App` + `bootstrap`) wrapped in
       `ProviderScope`; thin `main.dart` / `main_prod.dart` entrypoints
- [x] 3.2 Pinned-CA `HttpClient`/`dio` config sourced from `--dart-define`
       (`lib/src/network/api_client.dart` builds `Dio` from `AppConfig.apiBase`;
       **no** disable-verification switch; actual CA pinning wired per-flavor)
- [x] 3.3 Flavors `dev` and `prod` only (`Flavor` enum + `AppConfig`; `dev`
       → localhost, `prod` → deployed edge)
- [x] 3.4 Dev auth mode parity with backend: `AppConfig.devAuthMode` true only
       when `OIDC_ISS` absent **and** `DEV_AUTH_SUB` set; unreachable in `prod`

## 4. Repo hygiene
- [x] 4.1 `scripts/add-spdx-headers.sh` already covers `frontend-flutter/`
       (`.dart`/`.yaml`/`.feature`/`.sh`); re-run idempotent over the tree
- [x] 4.2 `dart format --set-exit-if-changed` + `flutter analyze` green on the
       seeded project (CI step advisory until `add-flutter-ci-tests` lands)
- [x] 4.3 Decide lint-plugin path (issue #289): `custom_lint` is archived and
       explicitly "no longer under active development" upstream; the official
       `analysis_server_plugin` (dart-lang/sdk) is the recommended path. DECISION:
       **migrate to `analysis_server_plugin`**. Updated proposal D1–D4, spec.md,
       AGENTS.md §5/§9, `flutter-ci.yml`, and the `flutter-lint-analysis` skill
       accordingly. The four rule IDs and exit policy are unchanged.
- [x] 4.4 `frontend-flutter/AGENTS.md` §5/§9 already reflects that the
       `breakdown_lints` rules run via `flutter analyze` (loaded by the
       analysis server, no separate runner) — conveyed by the #289
       `analysis_server_plugin` migration
