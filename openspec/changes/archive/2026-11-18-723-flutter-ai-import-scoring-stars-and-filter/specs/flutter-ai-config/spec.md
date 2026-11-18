<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## ADDED Requirements

### Requirement: Optional Decision Model configuration and split-billing key toggle
`AiConfigScreen` SHALL allow the user to configure or clear an optional Decision Model (`decisionProvider`, `decisionModel`). When the selected Decision Model provider matches the extraction provider, the screen SHALL display a **"Use same API key as extraction"** toggle (enabled by default). When the toggle is disabled or when the Decision Model provider differs from the extraction provider, the client SHALL resolve a remembered decision credential from `AiImportHandoffStore` or prompt for a separate API key bound to the Decision Model provider.

#### Scenario: Same provider reuses extraction key by default
- **WHEN** the user selects `neuralwatt` for both extraction and Decision Model and leaves "Use same API key as extraction" checked
- **THEN** the config save dispatches with `decisionVaultKeyId == vaultKeyId` without prompting for a second secret

#### Scenario: Unchecking same-key toggle binds a separate credential for split billing
- **WHEN** the user unchecks "Use same API key as extraction" and enters a second API key
- **THEN** the client creates a second `Settings` credential binding, stores its opaque reference in `AiImportHandoffStore`, and saves `AiConfig` with the distinct `decisionVaultKeyId`
