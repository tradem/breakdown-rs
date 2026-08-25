<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Android-First Flutter Project Scaffold
The Flutter app SHALL be created via `flutter create` as an Android-first
project under `frontend-flutter/`, with min SDK, Kotlin, and AGP versions
pinned. macOS is stubbed (target present but not configured) for later.

#### Scenario: A fresh checkout builds on Android
- **WHEN** a contributor runs `flutter build apk --flavor dev` on a fresh
  clone.
- **THEN** the build succeeds against the pinned toolchain versions with no
  "version not pinned" warnings.

### Requirement: Composition Root Uses Riverpod ProviderScope
`lib/main.dart` SHALL wrap the app in a single `ProviderScope`, wire the
dev/prod flavor from `--dart-define`, and construct a pinned-CA HTTP client.
No disable-verification switch is permitted in any code path.

#### Scenario: A developer tries to add a "trust all certs" debug switch
- **WHEN** a PR adds a bypass of TLS verification outside the dev flavor's
  pinned-CA set.
- **THEN** review rejects it under `flutter-client-authz` / cert-pinning
  rule; dev trusts go into the dev flavor's pinned CA set only.
