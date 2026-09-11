<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# add-android-release-workflow — Tasks

## 1. Signing key bootstrap (flutter-release-signing)

- [ ] 1.1 Write key-custody procedure doc (generation, offline backup by two
      maintainers, SHA-256 fingerprint recording, secret rotation); record the
      fingerprint constant in the doc for later `AllowedAPKSigningKeys` reuse.
- [ ] 1.2 Generate the release keystore offline; store `KEYSTORE_BASE64`,
      `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` as GitHub Actions
      repository secrets; distribute offline backups.
- [ ] 1.3 Extend `.gitignore` (`*.jks`, `*.keystore`, decode dirs) and add
      gitleaks rules covering keystore material in
      `frontend-flutter/**` and `.github/workflows/**`.

## 2. Gradle signing configuration

- [ ] 2.1 Add release signing config to
      `frontend-flutter/android/app/build.gradle.kts` reading
      `KEYSTORE_BASE64`/path, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
      `KEY_PASSWORD` from environment; fall back to unsigned release when
      absent; no credentials in the tree.
- [ ] 2.2 Verify locally: unsigned prod build succeeds without env vars;
      with env vars, `apksigner verify` prints the recorded fingerprint.
- [ ] 2.3 Add SPDX headers to all touched gradle/workflow files (monorepo
      header convention).

## 3. Release workflow (flutter-release-artifacts)

- [ ] 3.1 Create `.github/workflows/flutter-release.yml`: trigger on `v*`
      tags, SHA-pinned actions, `permissions: contents: write`, no
      `${{ github.event.* }}` in `run:` blocks.
- [ ] 3.2 Add version-consistency gate: parse tag vs.
      `frontend-flutter/pubspec.yaml` `version:` (and monotonic
      `versionCode`); fail with explicit error on mismatch.
- [ ] 3.3 Wire the existing CI quality gates as a reusable workflow call
      (format, analyze, test, drift check, gitleaks) gating publication.
- [ ] 3.4 Build step: `flutter build apk --release --flavor prod
      --split-per-abi` + `flutter build appbundle --release --flavor prod`;
      rename artifacts to `breakdown-<version>-<abi>.apk` /
      `breakdown-<version>.aab`.
- [ ] 3.5 Publish step: create/attach GitHub Release; pre-release flag when
      tag has `-alpha.N`/`-beta.N` suffix; release notes list APK per ABI
      with installation hint; idempotent on re-run.

## 4. Verification

- [ ] 4.1 Dry-run: push `v0.x.0-alpha.1` pre-release tag; confirm full
      artifact set on the GitHub pre-release and signature fingerprint.
- [ ] 4.2 Sideload the arm64 APK on a test device; verify install and that a
      follow-up build with the same key updates in place.
- [ ] 4.3 Negative tests: mismatched tag fails the gate; failing CI gate
      blocks publication; workflow re-run does not duplicate artifacts.

## 5. Documentation

- [ ] 5.1 Document the release process (tag → release) in
      `frontend-flutter/` docs, including pre-release conventions and the
      pubspec-version rule.
- [ ] 5.2 Cross-reference follow-up changes `add-fdroid-inclusion` and
      `add-play-store-release` in the docs (distribution roadmap).
