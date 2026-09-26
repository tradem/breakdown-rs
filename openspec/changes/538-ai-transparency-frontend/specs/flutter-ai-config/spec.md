<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## ADDED Requirements

### Requirement: Admin AI-literacy helper text

The AI-config screen SHALL render a persistent helper card above the
first-run and configured forms addressed to the person operating the
configuration: what this configuration controls (the deployment's AI import
provider and models, the extraction prompts), that the configured provider
processes user-provided schedule/script documents, and the operator's duty
to configure the feature honestly (curated provider + models; no secret
material). The copy SHALL be localized ARB catalog copy and the card SHALL
be visible in both the first-run and configured states (EU AI Act Art. 4
AI-literacy support, (EU) 2024/1689).

#### Scenario: Helper text precedes both forms
- **WHEN** the config screen renders the first-run form or the configured
  form.
- **THEN** the literacy helper card renders above it in the scroll order.

#### Scenario: Helper copy stays catalog-sourced
- **WHEN** the static inline-copy gate (`tool/check_inline_copy.sh`) runs.
- **THEN** the helper card surfaces no user-facing string literal outside
  the ARB catalogs.
