# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)

@critical
Feature: Costume assignment (optimistic update + role denial)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  Covers the CQRS-on-client contract (AGENTS.md §4): a successful command is
  acknowledged immediately (optimistic overlay) and the read projection is
  reconciled afterwards; and the client-side AUTHZ-GATE (D6) that denies the
  assignment on the costume stream for an unprivileged caller.

  The costume assignment screen is not yet landed, so these scenarios are the
  acceptance contract and are tagged @pending until the screen ships.

  @pending
  Scenario: Command shows optimistically then reconciles with the projection
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open the costume assignment for season "1"
    And I assign costume "c-7" to character "ch-3"
    Then the costume assignment appears optimistically
    And the costume assignment projection refreshes

  @pending
  Scenario: Unprivileged caller is denied on the costume stream
    Given the app is launched in dev-auth mode
    And I am authenticated as a "viewer" user
    When I open the costume assignment for season "1"
    And I assign costume "c-7" to character "ch-3"
    Then the costume stream denies assignment with a denial
