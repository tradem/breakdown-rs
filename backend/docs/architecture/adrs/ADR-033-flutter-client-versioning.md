<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark (opencode-go) -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->

# ADR-033: Flutter Client Versioning & Release Mechanics

**Status**: Accepted
**Date**: 2026-09-04
**Author**: Tobias Rademacher (@tradem); Muse Spark (opencode-go)
**Supersedes**: —
**Related**: ADR-020 (Rust component versioning), ADR-021 (API path versioning),
  ADR-007 (frontend technologies and API communication), ADR-006 (utoipa/OpenAPI codegen)
**Source change**: `openspec/changes/flutter-login-and-app-shell` (spec `flutter-app-dialogs`)

---

## Context

The Flutter client (`frontend-flutter/`) currently carries the scaffold default
`version: 1.0.0+1` in `pubspec.yaml` with no versioning discipline behind it:
no `CHANGELOG.md`, no release tags (`git tag` shows only `core-v*`/`infra-v*`/
`api-v*`), no `package_info_plus` dependency, and no `APP_VERSION` handling in
`AppConfig`.

At the same time, the display surface is already specified: spec
`flutter-app-dialogs` (change `flutter-login-and-app-shell`) requires an
About/Info dialog showing the application version (CI-injected via
`--dart-define=APP_VERSION`, fallback `'unknown'`) and a Settings dialog
showing the active API base and flavor. The contract for *where* the version is
shown exists — the contract for *what the version is and how it is produced*
does not.

The backend has ADR-020 (per-crate independent SemVer, `cargo-release`
local-initiated, per-crate tags). The frontend is a different shape — a single
shippable artifact, not a library graph — so ADR-020 cannot be copied 1:1, but
its spirit (explicit versions, tag-gated releases, CI enforcement, changelog)
applies. Store constraints add a hard requirement ADR-020 never had: Google
Play demands a strictly increasing integer `versionCode` (max 2100000000) on
every upload, and Apple maps the same pair to `CFBundleShortVersionString` /
`CFBundleVersion` (relevant when the macOS target lands).

## Decision

### D1: Single source of truth — `pubspec.yaml` `version: X.Y.Z+N`

Unlike the backend's per-crate versions (ADR-020 D1), the client owns exactly
one version: `version: X.Y.Z+N` in `frontend-flutter/pubspec.yaml`.

- `X.Y.Z` (build-name) → Android `versionName`, later macOS/iOS
  `CFBundleShortVersionString`. Human-readable SemVer.
- `N` (build-number) → Android `versionCode`, later `CFBundleVersion`.
  **Strictly monotonically increasing**; every store upload carries a higher
  `N` than the previous one, including PATCH releases.

Rationale for the deliberate departure from ADR-020: the client ships as one
binary. There is no internal consumer graph that needs contract gates between
`core`/`data`/`features` — those layers are versioned and released together.

### D2: SemVer rules for the client

Applied to the user-visible and platform-contract surface:

- **MAJOR**: breaking change — raised minimum backend API version, Drift cache
  schema reset that invalidates installed caches, dropped OS/API-level support,
  removed supported flavor entrypoint.
- **MINOR**: additive features — new screens, new read-model queries, new
  optional settings; backward compatible with the pinned minimum backend.
- **PATCH**: bug fixes with no surface change; dependency-only updates.
- **`+N`**: bumped on **every** release build, regardless of X.Y.Z movement
  (a PATCH without an `N` bump is not uploadable to Play).

### D3: Release tags `flutter-vX.Y.Z`

Releases are cut as monorepo tags named `flutter-vX.Y.Z` (e.g.
`flutter-v1.2.0`). The prefix is unambiguous against the existing `core-v*` /
`infra-v*` / `api-v*` scheme and needs no further namespacing. The tag's
`X.Y.Z` MUST equal the `pubspec.yaml` build-name at the tagged commit; `N` is
taken from the tagged `pubspec.yaml` unless CI overrides it per D5.

### D4: `CHANGELOG.md` in `frontend-flutter/`

Keep-a-Changelog format, entries generated from conventional commits — the same
conventions as the backend crate changelogs. No release without a changelog
entry, mirroring the ADR-020 `cargo-release` discipline (done manually until a
`melos`/`fastlane`-equivalent is adopted, see Notes).

### D5: Build-time injection and runtime reading

- **Baseline** `X.Y.Z+N` is committed in `pubspec.yaml`.
- **CI overrides per build without committing**: `flutter build appbundle
  --build-name=<X.Y.Z> --build-number=<N>` (e.g. `N` from the CI run counter),
  plus metadata via `--dart-define=APP_VERSION=<X.Y.Z+N-or-tag>` alongside the
  existing defines (`API_BASE`, `OIDC_*`, …).
- **Runtime**: the display contract from spec `flutter-app-dialogs` stays
  authoritative — the Info dialog shows `APP_VERSION`, fallback `'unknown'`
  when the define is absent (local dev builds). `package_info_plus` is added
  as a dependency as the native-value reader (validates `version` /
  `buildNumber` against the injected define and serves future needs such as
  store-review diagnostics). No hardcoded version string in Dart code, per the
  existing no-hardcoded-values stance.
- **Drift check in CI** (analogous to the `openapi_drift` discipline): a job
  asserts that on a `flutter-v*` tag the tag version equals the `pubspec.yaml`
  build-name and that `APP_VERSION` was injected — failing the release build
  otherwise.

### D6: Display surface (no spec change needed)

Implementation happens inside the existing tasks of
`flutter-login-and-app-shell`: Info/About dialog (version, GNU AGPL-3.0 with
source-repository link, AI-usage notice) and Settings dialog (API base,
flavor, dev-only backend-URI override). This ADR only fixes the version
*production*; the *presentation* contract is already specified.

### D7: Release flow is manual, like the backend

Releases are owner-initiated locally (tag + changelog + store upload), not a
CI cron/PR job — mirroring ADR-020 D5 (`cargo-release` local-initiated). CI
gates (analyze, tests, drift checks); it does not cut releases.

## Consequences

### Positive

- One obvious version source (`pubspec.yaml`) instead of the current
  scaffold default nobody owns.
- Store-upload safety: the monotonic-`N` rule and the tag drift check make
  "forgot the versionCode bump" a CI failure instead of a rejected upload.
- The already-specified Info/Settings version display gets a defined input
  (`APP_VERSION` ← tag ← pubspec), closing the spec-to-build gap.
- macOS later inherits the whole scheme for free (`CFBundleShortVersionString` /
  `CFBundleVersion` map from the same pair).
- Changelog + tag conventions match the backend, so monorepo release notes
  stay uniform.

### Negative

- Manual discipline until tooling exists: no `cargo-release` equivalent is
  adopted yet, so tag/changelog/`N`-bump correctness rests on the release
  owner plus the CI drift check.
- `N` from a CI run counter is only monotonic per workflow; parallel release
  workflows or a CI migration can break monotonicity — the release owner must
  sanity-check `N` against the last store upload (Play rejects, it does not
  silently overwrite, so failure is loud but late).

## Alternatives Considered

1. **Per-package versioning like ADR-020** (e.g. separate versions for
   `vendor/breakdown_api`, `packages/breakdown_lints`): rejected — these are
   build-time inputs regenerated from `backend/openapi.yaml`, not independently
   shipped artifacts. Versioning them separately adds gates with no consumer.
2. **`package_info_plus`-only, no `APP_VERSION` define**: rejected — spec
   `flutter-app-dialogs` already contracts the define with an `'unknown'`
   fallback; changing the spec to save one define inverts the dependency
   (spec follows build, not the reverse).
3. **Fully managed versioning (Fastlane/Codemagic auto-bump)**: deferred —
   viable later, but introduces external state for the versionCode counter
   today. Revisit when store uploads become frequent.

## Notes

- Operational: adding `package_info_plus` is a `pubspec.yaml` + lockfile
  change only; no permission, no secret, no network surface.
- The `dart` MCP server (`dart mcp-server`, configured in
  `frontend-flutter/.mcp.json`) exposes `pub` and analyzer tools that can
  assist future release chores (e.g. `dart fix`, pub upgrades) from the agent.
- When the macOS target lands, no versioning change is needed; only the
  export/packaging docs gain a paragraph.
