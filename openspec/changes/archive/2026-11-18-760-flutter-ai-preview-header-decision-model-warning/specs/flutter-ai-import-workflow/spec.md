<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta (760-flutter-ai-preview-header-decision-model-warning)

## ADDED Requirements

### Requirement: The preview header names the provider and model prominently
The preview screen SHALL render the configured extraction naming as a header
card above the typed payload — the model as the primary line, the provider as a
secondary line — instead of a quiet `bodySmall` footnote. A long model id SHALL
stay on one line and ellipsize rather than wrap. The EU AI Act Art. 50
transparency wording SHALL remain present as the card's caption, resolved by the
SAME shared sentence the submit disclosure and the apply section render, so the
promotion never weakens or forks the disclosure.

#### Scenario: A configured import preview
- **WHEN** the caller has a resolved AI configuration
- **THEN** the preview shows a header card with the model as the primary line,
  the provider as the secondary line, and the Art. 50 sentence as the caption

#### Scenario: A long model id
- **WHEN** the configured assistant model id does not fit the card width
- **THEN** the model line stays on one line, ellipsizes, and no layout overflow
  is reported

#### Scenario: Nothing configured, or the discovery failed
- **WHEN** the caller has no configuration or the configuration discovery fails
- **THEN** the header renders the existing "no AI configuration" copy as a
  single line, without a model or provider line, and never an invented name

### Requirement: A missing Decision Model is disclosed, non-blocking
When a resolved configuration carries no Decision Model (`decisionProvider` and
`decisionModel` both unset), the preview SHALL render a non-blocking warning
card that names exactly the two consequences — Pass-2 wardrobe continuity
suggestions and the scene/synopsis ratings are skipped — and states that the
import still runs. The card SHALL offer an affordance into the AI configuration
screen and SHALL NOT gate, disable, or delay the apply. When a Decision Model is
configured, nothing extra SHALL render.

#### Scenario: No Decision Model configured
- **WHEN** the resolved configuration has no `decisionProvider`/`decisionModel`
- **THEN** the preview shows the warning card with both consequences, the
  "runs anyway" statement and the link to the AI configuration

#### Scenario: A Decision Model is configured
- **WHEN** the resolved configuration carries both Decision Model fields
- **THEN** no warning card renders anywhere on the preview

#### Scenario: The warning does not block the dispatch
- **WHEN** the warning card is visible and the reviewer acknowledges the review
- **THEN** the apply action is enabled and dispatches as usual

### Requirement: An unread configuration is never reported as an unset Decision Model
The Decision Model warning SHALL render only from a resolved, non-failed
configuration read. A pending discovery, an unconfigured account, and a failed
discovery SHALL render no warning: a failed read is a different fact from "no
Decision Model is set", and the header degrades to the existing
"unconfigured" disclosure copy instead.

#### Scenario: The configuration discovery failed
- **WHEN** the configuration read fails
- **THEN** the header shows the "no AI configuration" copy and no Decision
  Model warning is rendered

#### Scenario: The discovery is still pending
- **WHEN** the configuration read has not resolved yet
- **THEN** no Decision Model warning is rendered

#### Scenario: No configuration exists at all
- **WHEN** the discovery resolved to "no configuration"
- **THEN** no Decision Model warning is rendered (the naming card already
  states the missing configuration)

### Requirement: The disclosure reads one cached discovery
The header card and the Decision Model warning SHALL resolve the caller's
newest non-revoked configuration through the existing cached discovery provider
— the same configuration the import handler resolves — issuing no additional
network call.

#### Scenario: Both surfaces on one screen
- **WHEN** the preview renders the header card and the warning
- **THEN** exactly one configuration discovery is performed per container
