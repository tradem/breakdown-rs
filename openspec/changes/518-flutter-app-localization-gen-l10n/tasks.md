<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## 1. ADR & infrastructure

- [ ] 1.1 Author ADR-034 at `backend/docs/architecture/adrs/ADR-034-flutter-app-localization-gen-l10n.md` (status: Accepted; references issue #518 and this change; records rejected alternatives `slang`, `easy_localization`, Dart Fluent port; follows the ADR-032/033 client-ADR precedent) and link it from issue #518
- [ ] 1.2 Add `flutter_localizations` (SDK) and `intl` to `frontend-flutter/pubspec.yaml`; add `frontend-flutter/l10n.yaml` with `arb-dir: lib/l10n`, `template-arb-file: app_de.arb`, `output-localization-file: app_localizations.dart`, `synthetic-package: false`, `output-dir: lib/l10n/generated`, `nullable-getter: false`, `untranslated-messages-file: l10n-untranslated.txt`
- [ ] 1.3 Create the empty catalog `app_de.arb` / `app_en.arb` with a first smoke key (`appTitleBreakdown`), run `flutter gen-l10n`, commit the generated `lib/l10n/generated/` output, and verify the imports compile
- [ ] 1.4 Wire `MaterialApp.router` in `lib/app.dart`: `localizationsDelegates`, `supportedLocales: AppLocalizations.supportedLocales` (`de`, `en`); verify Material-owned surfaces (date picker cancel) render German on a `de-DE` device
- [ ] 1.5 Add the Riverpod `appLocalizationsProvider` (derived from the widget-resolved locale, per design D3) with a unit test proving it tracks the locale the root widget resolves — never an independent system-locale read
- [ ] 1.6 Add the CI gate to the frontend workflow: `flutter gen-l10n`, then fail when `l10n-untranslated.txt` exists and is non-empty, plus drift detection on the committed generated output (mirror of the OpenAPI drift step, SHA-pinned action, no `github.event.*` interpolation into `run:`)

## 2. Catalog seeding from the glossary

- [ ] 2.1 Extract all UI copy keys (labels, CTAs, dialog titles/bodies) from `docs/design/glossary.md` into ARB keys under the naming convention of design D4 (`appTitleBreakdown`, `seasonsCreate*`, `photosUpload*`, …), German strings verbatim; write the `en` counterparts; regenerate and commit
- [ ] 2.2 Document the glossary↔catalog workflow in `docs/design/glossary.md`: the glossary stays the index (icon → German label → context → copy key), the ARB catalog stores the strings; new screens record keys in both places in the same change

## 3. Screen migration (feature by feature, existing screens in fixed order)

For every feature folder: migrate all user-facing strings to catalog keys, run `dart format` + `flutter analyze`, update the feature's widget tests and goldens (goldens in `de`), and verify the untranslated-keys gate passes. No feature's optical behavior changes — text content stays semantic-identical (existing German strings become catalog values; stray English strings adopt the glossary German wording).

- [ ] 3.1 `lib/features/shell/` + `lib/features/app_info/` (chrome, nav, About/Info dialog; uses `package_info_plus` strings via placeholders)
- [ ] 3.2 `lib/features/seasons/` incl. setup wizard (`seasons_screen.dart` error-mapper maps problem `code` → catalog narrative; remove the ad-hoc hardcoded code→text map)
- [ ] 3.3 `lib/features/blocks/`, `lib/features/episodes/`
- [ ] 3.4 `lib/features/scenes/`, `lib/features/shooting_days/`, `lib/features/scene_shoots/` (replace hand-rolled date patterns with `intl` `DateFormat`; Soll/Ist labels per glossary)
- [ ] 3.5 `lib/features/costumes/`, `lib/features/characters/`, `lib/features/costume_categories/`
- [ ] 3.6 `lib/features/photos/` (upload narrative incl. AUTHZ-GATE denial texts)
- [ ] 3.7 `lib/features/reports/`, `lib/features/ai_import/`
- [ ] 3.8 `lib/auth/` + cross-feature error/empty-state copy; the localized 403 narrative from `flutter-client-authz` now resolves through the catalog

## 4. Cross-cutting hardening

- [ ] 4.1 Problem-code narrative map: centralize `code` → (title, body, CTA) resolution over `ProblemError` driven by `appLocalizationsProvider` (branch on `code`, never `detail`; keep the AUTHZ-GATE pattern comments) with unit tests asserting both `Ok`/`Err` branches per design §5 error-hygiene
- [ ] 4.2 Sweep `lib/features/**` for remaining hardcoded user-facing strings (grep for `'…'` inside `Text`, `label*`, `tooltip*`, `hint*`, dialog copy) until the audit is empty; replace remaining hand-rolled date/number patterns with `intl`
- [ ] 4.3 Add one locale-aware widget test per tier-2 screen: pump the screen in `de` AND `en`, assert catalog strings and German-long-text layout survival (no fixed-width text truncation) on the seasons screen as reference (`first-screen-seasons` pattern)

## 5. Verification & wrap-up

- [ ] 5.1 Full local gate: `dart format --set-exit-if-changed`, `flutter analyze`, breakdown_lints runner, `flutter test --coverage` + coverde threshold, `flutter gen-l10n` + empty untranslated report
- [ ] 5.2 Integration smoke on device: verify German rendering on a `de-DE` device and English on an `en-US` device across the critical flows (season wizard, photo upload, Soll/Ist report)
- [ ] 5.3 Update `frontend-flutter/AGENTS.md` §6/§9 testing & codegen conventions with the l10n rules (catalog-only copy, gen-l10n before commit, goldens in `de`); cross-link ADR-034 in `backend/docs/architecture/adrs/README.md`
- [ ] 5.4 Close issue #518 when acceptance criteria are met; archive this change
