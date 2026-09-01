# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)

@critical
Feature: Continuity photo capture (AUTHZ-GATE to thumb)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  Exercises BOTH authorization gates for capture (AGENTS.md §5, D6):
    1. the client-side AUTHZ-GATE preflight (currentMembershipProvider) that
       must refuse the request before any network call leaves the device, and
    2. the server-side handler gate (SeasonPhotoAccessPolicy) that rejects the
       request even if it were issued.
  Then the happy path: upload -> projector-lag reconciliation -> thumbnail.

  The continuity photo screen is not yet landed, so these scenarios are the
  acceptance contract and are tagged @pending until the screen ships.

  @pending
  Scenario: Unprivileged capture is refused client-side before any network call
    Given the app is launched in dev-auth mode
    And I am authenticated as a "viewer" user
    When I request to capture a continuity photo
    Then no network request leaves the device
    And the backend rejects the capture with a denial

  @pending
  Scenario: Upload reconciles through projector lag to a thumbnail
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    When I open the continuity photo capture for scene shoot "ssh-1"
    And I upload a continuity photo for scene shoot "ssh-1"
    Then the continuity photo thumbnail for "ssh-1" appears
    And the continuity photo reaches terminal state
