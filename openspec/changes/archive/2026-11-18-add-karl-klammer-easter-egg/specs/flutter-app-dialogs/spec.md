<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Delta Spec: flutter-app-dialogs

## REMOVED Requirements

### Requirement: Settings Dialog with Dev-Only Backend-URI Override
**Reason**: The settings move from a dialog to a dedicated full screen
(issue #516) — the dialog is removed entirely; no dual entry point. The
functional scope (dev backend-URI override with validation, reset,
prod read-only display) migrates to the new capability
`flutter-settings-screen` without feature loss.
**Migration**: Open settings via the Mehr tab tile, which now pushes
`SettingsScreen` (`Navigator.push` + `MaterialPageRoute`, AppBar back
navigation). The Info dialog requirements of this capability are
unchanged.
