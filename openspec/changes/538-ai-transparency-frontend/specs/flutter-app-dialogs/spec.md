<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Modified Requirements

### Requirement: Info Dialog Contents

The app SHALL offer an About/Info dialog covering, in plain language:
(a) the application version, (b) the license (GNU AGPL-3.0) with a link
to the source repository, and (c) an AI usage notice stating that
schedule/script import features submit user-provided text to a
server-side configured AI provider and that the app itself never
communicates with an AI provider directly. The AI usage notice SHALL be
the doorway to a dedicated About-AI screen (`AiDisclosureScreen`) that
carries the expanded EU AI Act transparency disclosure; the dialog notice
SHALL remain and SHALL navigate to the screen on tap.

The About-AI screen SHALL carry six content blocks: (1) purpose of the
AI feature, (2) data flow of the import (device → backend → configured
provider → drafts → preview → apply), (3) provider/model naming read from
the caller's configured non-secret `AiConfigView` with an honest
degradation state when none is configured, (4) payload retention (imported
document payloads are garbage-collected after 7 days), (5) the EU AI Act
reference (Art. 4 AI literacy support, Art. 50 transparency, (EU)
2024/1689), and (6) the AGPL-3.0 / source-repository link. All copy SHALL
be localized ARB catalog copy; the screen spec SHALL live at
`docs/design/screens/about-ai.md` with a PlantUML Salt wireframe.

#### Scenario: Version display
- **WHEN** the dialog renders in a build where CI injected
  `--dart-define=APP_VERSION`.
- **THEN** the version shown equals that value; without it, the fallback
  `'unknown'` shows.

#### Scenario: AI notice navigates to the About-AI screen
- **WHEN** the user taps the dialog's AI notice.
- **THEN** the dedicated About-AI screen pushes over the dialog context and
  the dialog closes.

#### Scenario: Provider/model naming configured
- **WHEN** the About-AI screen renders and the caller has a configured
  `AiConfigView`.
- **THEN** block (3) names the configured provider and assistant model
  (non-secret wire values only; no vault reference, no prompt text).

#### Scenario: Provider/model naming unconfigured
- **WHEN** the About-AI screen renders with no configured `AiConfigView`
  (or the config fetch fails).
- **THEN** block (3) renders its honest degradation copy ("no AI
  configuration for this account") — no provider/model is invented.
