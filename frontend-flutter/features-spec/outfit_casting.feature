# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)

@critical
Feature: Outfit casting (optimistic update + variant deviation + role denial)
  Designated business-critical acceptance scope (AGENTS.md §6, spec
  flutter-gherkin-hybrid). End-to-end on device via flutter_gherkin.

  The wardrobe split (`separate-piece-and-outfit-domain`, issue #739) replaced
  costume assignment with **outfit casting**: a scene casts a character's
  composed look (`SceneOutfitBeat`), never a bare garment. Continuity comes
  from reusing the same `outfit_id`; a deviation is a copy-on-write variant
  (`CreateOutfitVariant`) so editing the fork never mutates scenes that
  reference the source.

  Covers the CQRS-on-client contract (AGENTS.md §4) — the command is
  acknowledged immediately and the read projection reconciles afterwards —
  plus the client-side AUTHZ-GATE (D6) that refuses an unprivileged caller on
  the look surface before any network call.

  Harness contract:
  - `AppHook.onBeforeRun` seeds the REAL dev backend over HTTP (`API_BASE`,
    host-resolved): season → block (creation auto-bootstraps the dev principal
    as an active costume-dept member in dev-auth mode) → two characters → two
    garments (repertoire-bound fundus rows, no character) → one look per
    character plus a variant of the first look → an episode → a scene with
    both characters assigned. The resolved REAL ids are mapped from the
    symbolic ids (season "1", "ch-3"/"ch-9", "p-7"/"p-r", "o-a"/"o-av"/"o-b",
    "e-1"/"sc-1") via `SeedCache` into `AppWorld.seedIds`.
  - The `I am authenticated as a "{string}" user` step flips the app's
    dev-auth membership override at runtime via the FlutterDriver data
    channel (`dev-membership:role=<role>`) — the runner builds the app once
    with fixed dart-defines, so a per-scenario membership shape cannot be a
    compile-time define. "viewer" yields a capability-less membership: the
    client-side AUTHZ-GATE denies every look command before its network call
    (read-model traffic stays allowed). The denial scenario therefore OPENS
    the character detail, where the look section renders the
    `outfit-denied-narrative` in place of the create action, and asserts the
    #380 request recorder proves zero look-command traffic left the device.

  Scenario: Casting a look onto a scene beat reconciles with the projection
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    And the backend is seeded with outfit "o-a" for character "ch-3" in scene "sc-1"
    When I open the scene detail for scene "sc-1"
    And I cast outfit "o-a" onto the beat of character "ch-3"
    Then the beat renders the look "o-a"
    And the look "o-a" carries its garment

  Scenario: Continuity reuses the same look, a deviation forks a variant
    # Continuity is an ID reference: casting the SAME look on a second beat is
    # the documented way to say "same wardrobe". A deviation must fork a
    # variant instead — editing the source would silently rewrite every scene
    # that references it.
    Given the app is launched in dev-auth mode
    And I am authenticated as a "costume_dept" user
    And the backend is seeded with outfit "o-a" for character "ch-3" in scene "sc-1"
    When I open the scene detail for scene "sc-1"
    And I cast outfit "o-a" onto the beat of character "ch-3"
    And I add a look change for character "ch-3" with outfit "o-av"
    Then the beat sequence of character "ch-3" shows "Gherkin Alltagslook" and "Gherkin Alltagslook Variante"

  Scenario: Unprivileged caller is denied on the look surface
    Given the app is launched in dev-auth mode
    And I am authenticated as a "viewer" user
    And the backend is seeded with outfit "o-a" for character "ch-3" in scene "sc-1"
    When I open the looks of character "ch-3"
    Then the look surface denies management with a denial
    And no look command leaves the device
