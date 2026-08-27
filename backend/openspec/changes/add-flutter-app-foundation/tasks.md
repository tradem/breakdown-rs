<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Tasks: add-flutter-app-foundation

> This change is the **Flutter foundation**: it provides `AGENTS.md`, the
> `.pi/skills/` directory, and the CI workflow that enforces the conventions.
> It does **not** generate Flutter/Dart application code — no `flutter
> create`, no `pubspec.yaml` with runtime deps, no `lib/main.dart`, no
> OpenAPI client, no screens. Those are implementation changes that consume
> the specs landed here and open as separate follow-up changes (listed in
> §"Out of scope").

> Apply model: Session 1 (this one) writes and commits the OpenSpec
> artifacts (`proposal` / `design` / `specs` / `tasks`). Session 2, on the
> same branch, runs `/opsx-apply` and lands the three foundation deliverables
> below (`AGENTS.md`, `.pi/skills/`, CI workflow). No feature code is
> produced in either session as part of *this* change.

## 0. Foundation-artifact completion (this change — Session 1)

- [x] 0.1 Open OpenSpec change `add-flutter-app-foundation` (branch
       `feat/add-flutter-app-foundation`)
- [x] 0.2 `proposal.md` — scope, 8 locked decisions (D1–D8), 4 resolved
       questions (Q1–Q4), non-goals
- [x] 0.3 Delta specs for each locked decision / resolved question:
       `flutter-openapi-client`, `flutter-state-management`,
       `flutter-test-pyramid`, `flutter-client-authz`,
       `flutter-offline-scope`, `flutter-gherkin-hybrid`,
       `flutter-openspec-home`, `flutter-genui-policy`
- [x] 0.4 `design.md` (the `AGENTS.md` content) — 10 sections mirroring the
       backend `AGENTS.md` layout
- [x] 0.5 `tasks.md` — this file, scoped to foundation deliverables only
- [x] 0.6 `openspec validate add-flutter-app-foundation` passes ✅
- [x] 0.7 Commit the OpenSpec artifacts on `feat/add-flutter-app-foundation`
       (landed in commit `569d162` on the change branch)
- [x] 0.8 Open PR for review of the foundation artifacts
       (https://github.com/tradem/breakdown-rs/pull/269)

## 1. `frontend-flutter/AGENTS.md` (foundation deliverable — Session 2 apply)

- [x] 1.1 Create directory `frontend-flutter/` at the monorepo root
- [x] 1.2 Copy `design.md` verbatim to `frontend-flutter/AGENTS.md`
       (byte-identical; the OpenSpec artifact remains the source of truth,
       the on-disk file is the convenience copy consumed by coding agents
       working inside `frontend-flutter/`) — `diff -q` confirms identical
- [x] 1.3 Apply SPDX header + co-authored-by convention to the file (the
       header is already in `design.md`; verified it survives the copy)
- [x] 1.4 Commit on `feat/add-flutter-app-foundation`

## 2. Ported pi-code skills (foundation deliverable — Session 2 apply)

- [x] 2.1 Create directory `frontend-flutter/.pi/skills/`
- [x] 2.2 Port lint/analysis guidance skill from `flutter/agent-plugins`
       (SPDX header; map to `analysis_options.yaml` expectations + custom
       lint rule names referenced in `design.md` §5/§6) —
       `flutter-lint-analysis/SKILL.md`
- [x] 2.3 Port testing recipes skill (widget test scaffolding, golden
       setup, `integration_test` harness, `flutter_gherkin` wiring) from
       `dart-lang/skills` / `flutter/agent-plugins` —
       `flutter-testing-recipes/SKILL.md`
- [x] 2.4 Port codegen conventions skill (`build_runner`, `freezed`,
       `json_serializable`, `riverpod_generator`, `drift_dev`,
       `openapi_generator`) from `dart-lang/skills` —
       `flutter-codegen-conventions/SKILL.md`
- [x] 2.5 Port Material 3 / ThemeData design skill from
       `flutter/agent-plugins` — `flutter-material3-theme/SKILL.md`
- [x] 2.6 Each ported skill carries an SPDX header + co-authored-by, and a
       provenance note (upstream repo + path) at the top of its `SKILL.md`
       (frontmatter `provenance:` field + a provenance blockquote under the
       H1; SPDX + co-authored-by as HTML comments after frontmatter)
- [x] 2.7 Commit on `feat/add-flutter-app-foundation`

## 3. CI workflow (foundation deliverable — Session 2 apply)

- [x] 3.1 Add `.github/workflows/flutter-ci.yml` triggered on PRs touching
       `frontend-flutter/**`
- [x] 3.2 Steps: `dart format --set-exit-if-changed`, `flutter analyze`
       (with the lint rule names the skills document; the actual
       `analysis_options.yaml` lands with the scaffold follow-up — until
       then this step runs against Flutter's defaults and is advisory-only,
       documented as such in the workflow)
- [x] 3.3 `gitleaks` scan over `frontend-flutter/**`
       (`.dart`/`.yaml`/`.arb`/`.md`) — downloads and SHA-256-verifies the
       pinned Gitleaks CLI binary (not a `gitleaks-action` SHA); the global
       `.md` allowlist limitation is
       resolved by issue #278 (scoped `frontend-flutter/.gitleaks.toml` + a
       frontend-flutter-only gitleaks CI step that scans `*.md`)
- [x] 3.4 SHA-pin every third-party action (40-char SHA + `# vX`
       comment); wire Dependabot bumps via `.github/dependabot.yml` (extend
       the backend config if it does not already cover `frontend-flutter/`) —
       the existing `github-actions` entry on `directory: /` already covers
       every workflow file in the repo (incl. this one), so no dependabot
       extension was required; a `pub`-ecosystem entry is deferred until a
       `pubspec.yaml` lands with `scaffold-flutter-project`
- [x] 3.5 The OpenAPI-client drift check, `flutter test --coverage`, and the
       `coverde` gate are **deferred** to the `add-flutter-ci-tests` follow-up
       (they require a real Flutter project to exist) — document this
       deferral as a comment in the workflow (deferred-jobs block at EOF;
       enabling the drift job MUST also add `backend/openapi.yaml` to the
       workflow's `paths:` filters so backend-only spec changes trigger it)
- [x] 3.6 Commit on `feat/add-flutter-app-foundation`

## Out of scope (separate follow-up changes, not in this foundation)

These are real implementation changes that consume the specs landed here.
Listed only as reminders; each opens its own change proposal with its own
`proposal.md` / `tasks.md`.

- `scaffold-flutter-project` — `flutter create`, `pubspec.yaml` with runtime
  deps, `lib/main.dart` composition root, flavors `dev`/`prod`,
  `analysis_options.yaml` with the custom lint rules (Task 3.2 of this change
  becomes enforceable here)
- `wire-openapi-dart-client` — `regen-client.sh`, `lib/api/generated/`,
  drift-check step enabled in CI
- `add-flutter-ci-tests` — `flutter test --coverage` + `coverde` gate
  enabled in CI
- `wire-flutter-oidc-auth` — OIDC PKCE client, `flutter_secure_storage`,
  `currentMembershipProvider`, cert pinning
- `add-drift-read-cache` — Drift database, repository cache pattern
- `add-gherkin-critical-scenarios` — `features-spec/` + `flutter_gherkin`
  wiring + designated critical `.feature` files
- `first-screen-seasons` — reference screen (SeasonsScreen) as the pattern
  for all subsequent screen-by-screen work
- `migrate-openspec-to-monorepo-root` — move `backend/openspec/**` to
  `/openspec/**` (see `flutter-openspec-home` delta)
- macOS build configuration (Android-first; macOS deferred)
- `frontend-web/` SvelteKit work (separate track)
- Offline command queue / conflict resolution (deferred; see
  `flutter-offline-scope` delta)
- ADR-007 amendment to correct the `POST /commands/{aggregate}/{action}`
  sketch against the actual resource-REST `openapi.yaml`
