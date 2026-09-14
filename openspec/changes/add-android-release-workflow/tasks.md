<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# add-android-release-workflow — Tasks

## 1. Signing key bootstrap (flutter-release-signing)

- [x] 1.1 Write key-custody procedure doc (generation, offline backup by two
      maintainers, SHA-256 fingerprint recording, secret rotation); record the
      fingerprint constant in the doc for later `AllowedAPKSigningKeys` reuse.
      → `frontend-flutter/docs/release-signing-key-custody.md` (fingerprint
      placeholder `TBD` — it is filled during the offline keystore generation,
      task 1.2).
- [ ] 1.2 Generate the release keystore offline; store `KEYSTORE_BASE64`,
      `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` as GitHub Actions
      repository secrets; distribute offline backups. *(operator task —
      offline keystore generation + secret entry, not agent-automatable;
      procedure: docs/release-signing-key-custody.md)*
- [x] 1.3 Extend `.gitignore` (`*.jks`, `*.keystore`, decode dirs) and add
      gitleaks rules covering keystore material in
      `frontend-flutter/**` and `.github/workflows/**`
      (rules `breakdown-signing-credential` +
      `breakdown-keystore-base64-blob` in root and scoped config).
- [ ] 1.4 Provision a protected GitHub `release` environment BEFORE enabling
      the release workflow (required reviewers, self-review prevention,
      administrator bypass disabled, deployment restricted to `v*` tags);
      scope `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
      `KEY_PASSWORD` to the environment and declare `environment: release`
      in the workflow, so a write-access user cannot exfiltrate the values
      via a modified workflow run. If the repository plan does not support
      these environment rules, use a separate protected release repository
      or signing service instead. *(code part done — `environment: release`
      declared in flutter-release.yml; the environment provisioning itself
      is an operator task)*

## 2. Gradle signing configuration

- [x] 2.1 Add release signing config to
      `frontend-flutter/android/app/build.gradle.kts` reading
      `KEYSTORE_BASE64`/path, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
      `KEY_PASSWORD` from environment; fall back to unsigned release when
      absent; no credentials in the tree. *(plus dev/prod Gradle
      productFlavors — decision in session: `--flavor prod` requires them;
      one shared application ID on purpose)*
- [x] 2.2 Verify locally: unsigned prod build succeeds without env vars;
      with env vars, `apksigner verify` prints the recorded fingerprint.
      *(verified with a throwaway keystore: unsigned build ✓, signed build
      ✓ fingerprint `cc43…` printed ✓, partial-config fails loudly ✓; the
      PROJECT fingerprint gets recorded at bootstrap 1.2)*
- [x] 2.3 Add SPDX headers to all touched gradle/workflow files (monorepo
      header convention).

## 3. Release workflow (flutter-release-artifacts)

- [x] 3.1 Create `.github/workflows/flutter-release.yml`: trigger on `v*`
      tags, SHA-pinned actions, `permissions: contents: write`, no
      `${{ github.event.* }}` in `run:` blocks.
- [x] 3.2 Add version-consistency gate: parse tag vs.
      `frontend-flutter/pubspec.yaml` `version:` (and monotonic
      `versionCode`); fail with explicit error on mismatch.
      *(gate logic unit-tested locally: match/mismatch/format/non-monotonic
      scenarios)*
- [x] 3.3 Wire the existing CI quality gates as a reusable workflow call
      (format, analyze, test, drift check, gitleaks) gating publication.
- [x] 3.4 Build step: `flutter build apk --release --flavor prod
      --split-per-abi` + `flutter build appbundle --release --flavor prod`;
      rename artifacts to `breakdown-<version>-<abi>.apk` /
      `breakdown-<version>.aab`; verify APKs with `apksigner verify
      --print-certs` against the recorded fingerprint, verify the AAB with
      `jarsigner -verify` (same keystore) plus a `bundletool build-apks`
      round-trip re-verified with `apksigner` (`apksigner` accepts APKs
      only). *(checksum-pinned bundletool 1.18.1; full chain verified
      locally with a throwaway keystore)*
- [x] 3.5 Publish step: create/attach GitHub Release; pre-release flag when
      tag has `-alpha.N`/`-beta.N` suffix; release notes list APK per ABI
      with installation hint; idempotent on re-run.
- [x] 3.6 Extend `.github/workflows/flutter-ci.yml` with a `workflow_call`
      trigger so task 3.3's reusable gate can actually run, and align its
      `version-drift` validator with the unified tag/pubspec format
      (`v*` release tags; pubspec version `X.Y.Z[-alpha.N|-beta.N]+N`);
      pass the tag ref into the reusable call for the version comparison
      (`release_ref` input).

## 4. Verification

- [ ] 4.1 Dry-run: push `v0.x.0-alpha.1` pre-release tag; confirm full
      artifact set on the GitHub pre-release and signature fingerprint.
      *(requires tasks 1.2/1.4 bootstrap; workflow-ready)*
- [ ] 4.2 Sideload the arm64 APK on a test device; verify install and that a
      follow-up build with the same key updates in place.
      *(operator task, on-device)*
- [ ] 4.3 Negative tests: mismatched tag fails the gate; failing CI gate
      blocks publication; workflow re-run does not duplicate artifacts.
      *(mismatch/format/monotonicity logic locally verified; the
      GitHub-side negative runs need the bootstrapped environment)*

## 5. Documentation

- [x] 5.1 Document the release process (tag → release) in
      `frontend-flutter/` docs, including pre-release conventions and the
      pubspec-version rule. → `frontend-flutter/docs/release-process.md`
- [x] 5.2 Cross-reference follow-up changes `add-fdroid-inclusion` and
      `add-play-store-release` in the docs (distribution roadmap).
