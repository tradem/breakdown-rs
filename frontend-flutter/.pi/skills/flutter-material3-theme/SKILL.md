---
name: flutter-material3-theme
description: Apply the breakdown-rs Material 3 design system — theme tokens under lib/design/, no hardcoded colors/type/spacing in widgets, per-flavor ThemeData. Use when scaffolding or reviewing widgets/ui components in frontend-flutter/.
license: AGPL-3.0
compatibility: Requires the Flutter SDK. Theme/token classes land under lib/design/ with the `scaffold-flutter-project` follow-up; until then apply these conventions to any prototyped components and to the eventual scaffold.
metadata:
  author: breakdown-rs
  version: "1.0"
  provenance: |
    Portable subset described in upstream `flutter/agent-plugins` (Material 3 /
    ThemeData design skill), adapted to breakdown-rs conventions. This
    SKILL.md is the authoritative breakdown-rs version. Upstream tracks the
    portable-subset structure; the rules below encode design.md §9 (Design
    System & Code Generation) and reinforce the `no_hardcoded_colors` /
    `no_hardcoded_text_styles` lints from the `flutter-lint-analysis` skill.
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Material 3 & ThemeData Design

> **Provenance:** Ported from the portable subset described in upstream
> `flutter/agent-plugins` (Material 3 / ThemeData design skill), adapted to
> breakdown-rs conventions. Authoritative source: `frontend-flutter/AGENTS.md`
> §9 (Design System & Code Generation).

## The hard rule (single source of tokens)

**Reusable components live under `lib/design/`; theme tokens are the single
source for colors, type, and spacing. No hardcoded colors/styles inline in
widgets.** (design.md §9.)

This is reinforced structurally by the `no_hardcoded_colors` and
`no_hardcoded_text_styles` custom lints (see `flutter-lint-analysis`). A widget
that reaches for `Color(0xFF...)`, `Colors.red`, or `TextStyle(fontSize: 14)`
inline is rejected at review.

## Target layout

```
frontend-flutter/lib/design/
├── tokens/
│   ├── colors.dart        # BreakdownColorScheme (light/dark from seed)
│   ├── typography.dart     # BreakdownTypography (Material 3 type scale)
│   └── spacing.dart        # BreakdownSpacing (4/8/16/24/32 grid)
├── theme.dart             # appTheme(Brightness) -> ThemeData
├── components/            # reusable Material 3 components (BreakdownCard, …)
└── extensions/            # ThemeExtension<BreakdownColors> etc.
```

- `lib/main.dart` wires `ThemeData` per flavor (dev/prod) — dev may surface a
  dev banner; colors must still come from tokens (a deterministic variant, not
  a hardcoded `Colors.red`).
- Dark/light come from a single seed via `ColorScheme.fromSeed`
  (Material 3 dynamic color); the seed is a token, not a literal in widgets.

## Conventions

### Colors
```dart
// ✅ from a token / theme
final colors = Theme.of(context).extension<BreakdownColors>()!;
Container(color: colors.surfaceElevated);

// ❌ forbidden
Container(color: Color(0xFF1E1E1E));
Container(color: Colors.red);
```

### Typography
```dart
// ✅
Text('S01', style: Theme.of(context).textTheme.titleMedium);

// ❌
Text('S01', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold));
```

### Spacing
```dart
// ✅ token grid (4/8/16/24/32)
Padding(padding: BreakdownSpacing.l.all); // 16

// ❌ magic numbers
Padding(padding: EdgeInsets.all(13));
```

### Components
- Reusable UI atoms/molecules live under `lib/design/components/` (e.g.
  `BreakdownCard`, `BreakdownStatusChip`). Feature widgets consume them; they
  do not re-derive Material 3 styling inline.
- Status chips that encode domain state (processing / stale / error) map
  domain values → token colors, never raw `Colors.amber` / `Colors.red`.

## Per-flavor theme wiring

- `dev` flavor: seed from dev token set; optional dev banner. May trust a
  dev-pinned CA set (see `flutter-client-authz` spec) — but never a
  "disable-verification" switch.
- `prod` flavor: prod token set; `REQUIRE_IN Transit-FLS`-grade posture
  mirroring the backend.
- Flavors are wired via `--dart-define` at build; no other flavors without a
  change proposal.

## Dynamic color / Material You

- The app uses a **seeded** `ColorScheme` (deterministic brand seed), not
  on-device dynamic color, so the brand is consistent across users/flavors.
  Per-device dynamic color may be revisited later as a flavor opt-in; it is not
  the default.

## Review checklist

- [ ] No inline `Color(0xFF…)` / `Colors.*` / raw `TextStyle` in widgets?
- [ ] Spacing on the 4/8/16/24/32 token grid (no magic `EdgeInsets.all(13)`)?
- [ ] Reusable styling extracted to `lib/design/components/` (not duplicated)?
- [ ] Dark/light derived from the seeded `ColorScheme`, not hand-maintained pairs?
- [ ] Domain-value → color mapping lives in a token-backed component, not inline?
- [ ] Flavor differences wired via `--dart-define` (no inline flavor `if`)?
