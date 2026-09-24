<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

The Flutter client renders all user-facing copy from hardcoded inline
strings — mixed English and German — with no `flutter_localizations`,
`intl`, or message catalog. Yet the conventions already assume one:
`frontend-flutter/AGENTS.md` scopes gitleaks at `.arb` files, requires a
localized 403 narrative, and requires UI copy per RFC 9457 problem `code`
to be localized client-side. `docs/design/glossary.md` declares German
labels + copy keys the single source of truth for UI copy. Issue #518
researched the options and the decision is settled (ADR-034): the
official pipeline — `flutter_localizations` + `flutter gen-l10n`
(ARB) + `intl`.

The backend localizes problem `detail` server-side via Fluent
(`error-localization` spec). That is a *server* concern and stays one:
the client never renders backend `detail`; it branches on the stable
`code` and shows its own localized narrative. There is therefore
**no `.ftl` sharing** between backend and client — the two message layers
have different vocabularies (server: one-sentence `detail`; client:
title/body/CTA/dialog narratives).

## Goals / Non-Goals

**Goals:**

- Official, zero-third-party message pipeline: ARB catalog, build-time
  generated `AppLocalizations`, compile-time key safety.
- German (`de`) as the template locale (glossary labels are the
  canonical shipped copy); English (`en`) as second locale.
- All user-facing copy in `lib/features/**` sourced from the catalog —
  no hardcoded strings left behind.
- Problem-`code` narratives (including the client-side AUTHZ-GATE 403
  narrative) resolved through catalog keys, never from backend
  `detail`.
- Deterministic CI gate: `flutter gen-l10n` + fail when the
  parsed untranslated-messages JSON report contains untranslated
  entries (a complete catalog writes `{}` and passes; mirrors the
  OpenAPI drift gate).
- `intl`-based date/number formats everywhere.
- Minimal-invasive access convention for non-widget layers
  (controllers/validators) that already hold a `BuildContext` or locale.

**Non-Goals:**

- Additional locales beyond `de`/`en`; RTL audit beyond framework
  defaults; pseudo-locale tooling.
- Any backend change, including `backend/openapi.yaml`, the Fluent
  bundles, or the `error-localization` spec.
- An in-app language picker in this change (device locale drives the
  app; a picker can ride on the same provider later).
- Offline translation or TMS integration (the ARB format keeps that
  door open).

## Decisions

**D1 — Official gen-l10n over `slang` / Fluent port / `easy_localization`.**
Rejected alternatives (researched in issue #518, recorded in ADR-034):
`slang` (best DX, context-free `t`, but third-party dependency +
non-standard format in a codegen-first, supply-chain-averse repo);
Dart Fluent port `fluent`/`fluent_flutter` (syntactic parity with the
backend's `.ftl`, but runtime parsing — typos surface at runtime, no CI
gate — and small-adoption community packages); `easy_localization`
(runtime string keys, no compile-time safety at all). The official
pipeline's prices (`BuildContext` access, verbose ARB metadata blocks,
flat keys) are acceptable and consistent with the repo's existing
codegen discipline (Drift, Riverpod, freezed, OpenAPI client).

**D2 — Template locale `de`, second locale `en`.**
The glossary defines the shipped copy as German; the template ARB
(`app_de.arb`) therefore holds the canonical strings and `@`-metadata
(placeholders, descriptions). `app_en.arb` is the secondary locale.
Both must be complete — the CI gate fails on untranslated keys, so
`en` does not silently fall back. `flutter_localizations` delegates are
declared for both locales so Material-owned surfaces (date pickers,
tooltips, a11y labels) follow the device locale too.

**D3 — Access convention: `AppLocalizations.of(context)` at the widget
edge; an `appLocalizationsProvider` (Riverpod) for controller/domain
narratives.**
Screens resolve copy in `build` via `AppLocalizations.of(context)`
(`nullable-getter: false`). Controllers and problem-code narrative
mappers, which run without a widget context, read the generated
instance through a Riverpod provider derived from the current locale
(kept in sync with `MaterialApp.router`'s resolution). This preserves
the "no `throw`/no hidden lookup" opaqueness rules: string resolution
stays an explicit, observable dependency, not a global locator in the
middle of `domain/`. Widget-facing mappers keep receiving the
resolved `AppLocalizations` object — same shape as today's error-mapper
callbacks in `seasons_screen.dart`, now fed from the catalog.

**D4 — Copy keys mirror the glossary; nesting via naming convention.**
gen-l10n has flat keys, so the glossary's per-feature copy keys become
snake-style prefixed ARB keys (`seasons_create_title`,
`photos_upload_error_retrying`, `authz_denied_narrative`, …). The
glossary remains the human index (key → usage context → icon); the ARB
catalog is the string storage. Every screen spec / new screen records
its keys in both places in the same change (extends the existing
glossary workflow, §design docs).

**D5 — Plurals/placeholders via ICU Message Syntax in ARB.**
Counts (e.g. a photo-count label), dates and numbers use ICU
plural/select and `intl`-typed placeholders (`int`, `DateTime`,
`num`) declared in the `@key` metadata — no manual string
interpolation of user-visible text anywhere in `lib/` outside ARB
placeholder declarations. Any missing catalog key is a compile-time
error via `nullable-getter: false`.

**D6 — Two CI gates with distinct responsibilities.**
Catalog completeness and the absence of hardcoded inline copy are
different guarantees and are enforced separately — a widget retaining an
inline string references no ARB key, so generation and compilation can
both pass while that copy stays untranslated.

1. **Catalog completeness (untranslated-keys gate).** CI runs
   `flutter gen-l10n` with `untranslated-messages-file`, then **parses
   the JSON report and fails only when it contains untranslated
   entries**. A fully translated catalog yields an empty object `{}`,
   not an empty file, so a file-size check would false-positive; the
   gate keys on report content. It covers keys that exist in the
   template but cannot see copy that was never turned into a key.
2. **Inline user-facing literals (static audit).** A separate, bounded
   static check / migration audit over `lib/features/**` — string
   literals in `Text`, `label*`, `tooltip*`, `hint*`, dialog copy,
   snackbars — blocks new hardcoded copy from entering and drives the
   migration sweep (task 4.2). This is the enforcement the catalog gate
   cannot provide.
3. **Drift check.** CI runs message generation into a throwaway then
   diffs the **generated directory** against the committed tree —
   covering all generated `.dart` output including
   `app_localizations.dart`, not just formatting via `dart format` and
   not only `.g.dart` files — and fails on any difference. gitleaks
   already covers `.arb`.

**D7 — Generated output checked in, read-only.**
`gen-l10n` output (`.dart_tool` default or `synthetic-package: false`
into `lib/l10n/generated/`) is committed like Drift/Riverpod/freezed
outputs — regenerate, never hand-edit (flutter-codegen-conventions
skill / AGENTS.md hard rule). A concrete decision inside this change:
`synthetic-package: false` with `output-dir: lib/l10n/generated`, so
imports are regular package imports and CI drift detection works on
committed files.

**D8 — `AppWidget` wiring.** `MaterialApp.router` grows
`localizationsDelegates: AppLocalizations.localizationsDelegates`,
`supportedLocales: AppLocalizations.supportedLocales`, and the flavor
independent default `locale` resolution (device locale, `de` fallback
on `Intl.systemLocale` mismatch via gen-l10n's own fallback chain:
template locale is the ultimate fallback).

## Risks / Trade-offs

- [German runs ~30% longer than English — layout regressions] →
  Widget tests run in `de` (the tightest locale); goldens per screen
  re-baselined in `de`; use `Flexible`/`Wrap` on copy-critical rows
  during migration (no fixed-width text containers).
- [Big-bang string migration could hide semantic drift (accidentally
  changed copy)] → Migration is mechanical per feature folder; the
  German template strings are taken verbatim from the glossary /
  existing screens; where existing strings are mixed-language, the
  glossary copy wins. Reviewer spot-check per feature, not per line.
- [`AppLocalizations.of(context)` boilerplate in every widget] →
  Accepted (D1 trade-off); a thin `context.l10n` extension in
  `lib/design/` or per-feature is allowed if the repetition hurts —
  no context-free global accessor.
- [Riverpod provider for non-widget access could drift from the
  MaterialApp-resolved locale] → The provider derives *from* the
  widget-resolved locale (a `ProviderScope` override set during
  `build` of the root widget), never from an independent
  `Intl.systemLocale` read.
- [gen-l10n regenerates on every CI run → merge conflicts in generated
  files] → Same discipline as existing `.g.dart` files;
  `flutter gen-l10n` before commit (canonically via the same
  `build_runner`/`scripts` entry point used by the codegen skill).

## Migration Plan

1. ADR-034 lands first (task 1.1) — decision record before code.
2. Infrastructure: dependencies + `l10n.yaml` + delegates + CI gate +
   empty catalog (tasks 1.x–2.1).
3. Feature-by-feature migration, existing screens in a fixed order
   (seasons → shell/app_info → blocks/episodes → scenes …), each with
   its widget-test/golden updates in the same task.
4. Problem-code narrative map last (cross-feature surface).
5. Rollback: single revert of the change branch; no data migration, no
   wire change, no stored state touched (catalog is static assets).

## Open Questions

- Should `docs/design/screens/*.md` wireframes gain explicit
  locale-pairing requirements (goldens in `de` only) now or when the
  first second-locale defect appears? → default: keep goldens in `de`
  only; revisit on first `en` regression.
