<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Sample token change (worked example)

Scenario: change the brand seed from Material teal to the (hypothetical)
breakdown-orange, and tighten `space8` from 8 to 6.

## 1. JSON change — `design/tokens/color.json`

```diff
     "brand": {
       "seed": {
         "$type": "color",
-        "$value": {
-          "colorSpace": "srgb",
-          "components": [0.0, 0.5882352941176471, 0.5333333333333333],
-          "hex": "#009688"
-        },
+        "$value": {
+          "colorSpace": "srgb",
+          "components": [0.7803921568627451, 0.47058823529411764, 0.0],
+          "hex": "#c77800"
+        },
         "$description": "Brand seed color driving ColorScheme.fromSeed …"
       }
     },
```

(`components` are normalized sRGB in [0,1]; the `hex` fallback must agree
exactly with `components` — the validator checks both.)

## 2. JSON change — `design/tokens/size.json`

```diff
       "8": {
         "$type": "dimension",
-        "$value": {"value": 8, "unit": "px"},
-        "$description": "Compact gap (AppSpacing.space8)."
+        "$value": {"value": 6, "unit": "px"},
+        "$description": "Compact gap (AppSpacing.space8)."
       },
```

(The token *name* stays `space8` — names are API, values are data.
Renaming a token is a breaking change: it shows up in the Dart diff below
and in hand-authored code that references it.)

## 3. Run the build

```bash
bash scripts/build-tokens.sh
```

The validator checks DTCG conformance, Style Dictionary regenerates, and
`design/dart-artifact.mjs` rewrites the Flutter artifact.

## 4. Generated Dart diff — `frontend-flutter/lib/design/gen/design_tokens.g.dart`

```diff
 abstract final class DesignTokens {
-  static const Color colorBrandSeed = Color(0xFF009688);
+  static const Color colorBrandSeed = Color(0xFFC77800);
```

```diff
-  static const double sizeSpace8 = 8.0;
+  static const double sizeSpace8 = 6.0;
```

## 5. Downstream (no further code edits)

- `AppThemes.light()`/`dark()` render the new seed via
  `ColorScheme.fromSeed(DesignTokens.colorBrandSeed)` — because all M3
  scheme roles are seed-derived, every role shifts automatically
  (Decision D4).
- `AppSpacing.space8` delegates to `DesignTokens.sizeSpace8` — widget call
  sites are untouched.

## 6. Verify before committing

```bash
flutter test                                    # frontend-flutter/ — goldens will
                                                # fail by design; regenerate them
                                                # only if the visual change is
                                                # intended
git diff --stat                                 # JSON + design_tokens.g.dart together
bash scripts/build-tokens.sh && git status      # second run: clean tree
```

Commit rule: JSON change and regenerated `design_tokens.g.dart` land in the
same commit, or the CI drift gate fails the PR.
