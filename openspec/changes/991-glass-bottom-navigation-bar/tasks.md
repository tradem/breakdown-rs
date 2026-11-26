<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #991

## 1. Token source + format

- [x] 1.1 `design/validate-tokens.mjs` — support the DTCG `number` type
      (finite JSON number, no aliases), documented in the header comment and
      listed in the supported-type error message.
- [x] 1.2 `design/tokens/component.json` — new `component.navigationBar`
      group: `height` (80 px), `tintAlpha` (0.80), `planeLiftAlpha` (0.06),
      `blurSigma` (12 px), each with the decision it states in `$description`.
- [x] 1.3 `bash scripts/build-tokens.sh` — regenerated
      `frontend-flutter/lib/design/gen/design_tokens.g.dart` (74 → 78 tokens),
      committed with the JSON change; drift check (`DESIGN_TOKENS_OUT_DIR`)
      produces no diff.

## 2. Design system

- [x] 2.1 `lib/design/navigation_bar_metrics.dart` (new) — the single consumer
      of the four tokens; composes the opaque plane (surface lifted toward
      `surfaceTint`) and the translucent tint.
- [x] 2.2 `lib/design/theme.dart` — `NavigationBarThemeData` from tokens:
      height, translucent background, `elevation: 0`, transparent shadow and
      surface tint; indicator/label colors stay M3 defaults.
- [x] 2.3 `lib/design/components/glass_bottom_bar.dart` (new) — `ClipRect` +
      `BackdropFilter` surface; keyboard-open fallback paints the same plane
      opaque and drops the filter.

## 3. Shell

- [x] 3.1 `lib/features/shell/app_shell.dart` — compact `Scaffold` gets
      `extendBody: true`; the bar slot renders `GlassBottomBar`.
- [x] 3.2 The plus action's 80 dp clearance moves from the Column band into the
      body's bottom `MediaQuery` inset (one derived reservation; the #823 keyed
      marker keeps its per-destination presence semantics with no extent).
- [x] 3.3 The #824 status-bar single-count seam moves into the body, around the
      tab content only (the top bar keeps its own inset); the old
      `MediaQuery.removePadding` seam discarded the `extendBody` bottom padding.

## 4. Tests

- [x] 4.1 `test/design/navigation_bar_metrics_test.dart` (new) — token
      round-trips, the plane/tint derivation, the plane-composite identity,
      the sigma cap, and the contrast budget (labels ≥ 4.5:1, icons/indicator
      ≥ 3:1) against the worst-case blurred backdrop in both themes.
- [x] 4.2 `test/design/components/glass_bottom_bar_test.dart` (new) — structure
      (clipped `BackdropFilter`, translucent bar Material, elevation 0), the
      keyboard fallback, and two goldens over scrolled content.
- [x] 4.3 `test/features/shell/app_shell_test.dart` — glass present on compact /
      absent on rail+drawer, `extendBody` on compact only, the body inset equals
      the painted bar height, the plus band is added on Script only, and a
      34 dp gesture-nav inset is counted exactly once.
- [x] 4.4 Re-baselined goldens: `app_shell_compact_{light,dark}.png`,
      `app_shell_pushed_header_status_bar.png`, `account_drawer_{light,dark}.png`
      (the bar's surface is in frame); medium/expanded goldens unchanged.

## 5. Docs

- [x] 5.1 `docs/design/screens/navigation-shell.md` — compact wireframe note and
      the Components & Semantics row for the glass bar surface (tint/blur
      budget, keyboard fallback, painted-height inset, no glass on rail/drawer).
- [x] 5.2 `design/tokens/README.md` — the `number` type and the
      `component.navigationBar` group with its four decisions.
- [x] 5.3 `.pi/skills/design-tokens-dtcg/SKILL.md` — `number` in the type list
      and in the component-token rule.
- [x] 5.4 `CHANGELOG.md` entry + `pubspec.yaml` bump
      (`0.5.0-alpha.2+157 → 0.5.0-alpha.3+158`).
- [x] 5.5 This change records the token-type relaxation and the shell delta.

## 6. Verification

- [x] 6.1 `dart format --set-exit-if-changed .` clean.
- [x] 6.2 `flutter analyze` — only the two pre-existing generated-l10n
      deprecation infos remain; nothing from this change.
- [x] 6.3 `dart run bin/run_lints.dart ../..` (in `tool/breakdown_lints_runner`)
      — no violations.
- [x] 6.4 `flutter test` — full suite green (2585 tests).
- [x] 6.5 Token drift gate: `DESIGN_TOKENS_OUT_DIR=/tmp/... bash
      scripts/build-tokens.sh` + `diff -r` → no difference.
- [x] 6.6 `bash scripts/check-design-diagrams.sh` — all PlantUML blocks compile.
- [x] 6.7 `bash scripts/add-spdx-headers.sh --check` — no offender in this
      change (the ten pre-existing `.pi/skills/openspec-*` and
      `.pi/prompts/opsx-*` misses are unrelated).
- [x] 6.8 `openspec validate 991-glass-bottom-navigation-bar --strict` passes.

## Follow-ups (not this change)

- [ ] On-device frame check on a low-end Android device: if the save-layer
      drops frames, degrade to transparent-without-blur by dropping the
      `BackdropFilter` (the plan's documented fallback) — never to opaque.
- [ ] Decide the glass PAIR (a translucent shell top bar to match): explicitly
      out of scope here, needs its own change.
