<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-app-localization Delta (issue #518 — official gen-l10n message catalog)

## ADDED Requirements

### Requirement: Official gen-l10n message catalog
The Flutter client SHALL localize user-facing copy exclusively through
the official Flutter i18n pipeline — `flutter_localizations` +
`flutter gen-l10n` over ARB files with `intl` for formats — with a
German (`de`) template ARB holding the canonical messages (verbatim
per `docs/design/glossary.md`) and a complete English (`en`) ARB. The
generated `AppLocalizations` output SHALL be committed as a read-only
regenerate-only artifact (same discipline as other generated files).
The `l10n.yaml` configuration SHALL set `nullable-getter: false` so a
missing key is a compile-time error.

#### Scenario: Missing catalog key fails the build
- **WHEN** a widget references an `AppLocalizations` getter whose key
  is absent from `app_de.arb`
- **THEN** code generation or compilation fails instead of surfacing a
  runtime lookup error

#### Scenario: De template is canonical
- **WHEN** the German and English catalogs disagree on whether a key
  exists
- **THEN** CI fails via the untranslated-messages gate (same rule for
  both directions), keeping `de` and `en` key sets identical

### Requirement: Localization wiring in the app root
The app root (`MaterialApp.router`) SHALL declare
`localizationsDelegates: AppLocalizations.localizationsDelegates` and
`supportedLocales: AppLocalizations.supportedLocales` (`de`, `en`), so
Material-owned surfaces (date pickers, tooltips, accessibility labels)
and app copy both follow the resolved locale. The resolved locale SHALL
be the device locale, with the `de` template as the ultimate fallback.
A Riverpod provider SHALL expose the resolved `AppLocalizations` to
non-widget layers (controllers, problem-code narrative mappers), derived
from the widget-resolved locale — never from an independent
system-locale read.

#### Scenario: Material-owned surfaces follow the device locale
- **WHEN** the device locale is `de-DE` and a screen opens a Material
  date picker
- **THEN** the picker renders German framework copy (e.g.
  `'Abbrechen'` on the cancel button)

#### Scenario: Unsupported device locale falls back to German
- **WHEN** the device locale is a language other than `de` or `en`
- **THEN** the app renders the German template catalog without an
  untranslated-locale error

#### Scenario: Controller-side narrative uses the catalog
- **WHEN** a Riverpod controller builds a user-facing message for a
  problem `code` (e.g. `season.conflict`)
- **THEN** the narrative text is resolved from the generated catalog
  via the locale provider, not from a hardcoded string map

### Requirement: No hardcoded user-facing copy
Screens and widgets under `lib/features/**` SHALL source every
user-facing string from the message catalog. Diagnostic, developer, and
log strings that are never rendered to end users are exempt. Backend
problem `detail` text MUST NOT be displayed to users; error narratives
branch on the stable problem `code` and use client-owned catalog copy
(per the RFC 9457 client contract, ADR-031).

#### Scenario: Problem-code narrative instead of backend detail
- **WHEN** a command fails with 409 `season.conflict`
- **THEN** the screen shows the localized catalog narrative for that
  code (title/body/CTA) and never the raw backend `detail` member

#### Scenario: AUTHZ-GATE denial narrative is localized
- **WHEN** the client-side `currentMembershipProvider` role check denies
  an AUTHZ-GATE'd action before any network call
- **THEN** the user sees the localized 403 narrative from the catalog
  in the active locale

### Requirement: Plurals, placeholders, and formats via ICU and intl
User-visible counts, dates, times, numbers, and currencies SHALL use
ICU Message Syntax (plural/select) inside ARB messages with
placeholder metadata, and `intl` `DateFormat`/`NumberFormat` for value
formatting — never manual string interpolation of user-visible text in
Dart code.

#### Scenario: Pluralized detail count
- **WHEN** a costume shows a photo count of 1, and another of 3, in
  the German locale
- **THEN** the labels follow the German plural rules of the ICU
  message (e.g. `'1 Foto'` vs `'3 Fotos'`) rather than a manual
  `'$n Fotos'` template

#### Scenario: Locale-aware date rendering
- **WHEN** a shooting day date renders under locale `de`
- **THEN** the format comes from `intl` `DateFormat` for that locale
  (e.g. `d. MMMM y` semantics), not a hardcoded pattern string

### Requirement: CI untranslated-keys gate
Frontend CI SHALL run message generation and fail when the configured
`untranslated-messages-file` exists and is non-empty, mirroring the
OpenAPI-client drift gate; the committed generated output SHALL match
regeneration exactly. gitleaks scans the `.arb` catalog files.

#### Scenario: Untranslated key blocks the pipeline
- **WHEN** a PR adds a key to `app_de.arb` without the `en` counterpart
- **THEN** CI fails the untranslated-keys gate with a
  regenerate-and-complete instruction

### Requirement: Glossary remains the copy key index
`docs/design/glossary.md` SHALL remain the single human index of copy
keys (Material Symbols icon → user-facing German label → usage
context → copy key); the ARB catalog is the string storage for those
keys. New screens SHALL record their copy keys in the glossary and in
the ARB catalog in the same change.

#### Scenario: New screen introduces copy
- **WHEN** a screen change adds a new label `'Neue Drehplan-Version'`
- **THEN** the same change adds the glossary row (label, context, copy
  key) and the ARB entries in `de` and `en`, and CI passes the
  untranslated-keys gate
