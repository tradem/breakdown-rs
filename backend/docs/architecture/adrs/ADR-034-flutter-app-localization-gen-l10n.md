<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# ADR-034: Flutter App Localization with the Official gen-l10n Pipeline

**Status**: Accepted  
**Date**: 2026-09-04  
**Related**: ADR-007, ADR-031, ADR-033  
**Source change**: `openspec/changes/518-flutter-app-localization-gen-l10n`  
**Issue**: #518

## Context

The Flutter client had no message catalog, `flutter_localizations`, or
locale-aware Material delegates. User-facing copy was inline in widgets and
was inconsistently German and English. The client also already had a contract
that problem `detail` is server-owned and must never be rendered: user-facing
error narratives are selected by the stable RFC 9457 `code` and localized on
the client.

The shipped UI language is German, with English as the second supported locale.
`docs/design/glossary.md` remains the human index for labels and copy keys;
the generated message catalog is the string storage. The backend Fluent files
remain server-owned and are not shared with the client.

## Decision

Adopt the official Flutter i18n pipeline:

- `flutter_localizations` for Material, Cupertino, and framework-owned copy;
- `intl` for locale-aware date and number formatting;
- ARB catalogs under `frontend-flutter/lib/l10n/`, with `app_de.arb` as the
  template and `app_en.arb` as the complete secondary catalog;
- `flutter gen-l10n` with `nullable-getter: false`; generated output is
  committed, but remains rebuild-only and is never hand-edited.

The root app supplies the generated delegates and supported locales. Device
locale drives resolution, with German as the ultimate fallback. Widget code
resolves copy at the widget edge through `AppLocalizations.of(context)`.
Non-widget narrative resolution receives the generated catalog through a
Riverpod provider whose value is supplied from the widget-resolved locale; it
must not independently read a system locale or use a global localization
service.

Counts and placeholders use ARB ICU Message Syntax. Date and number rendering
uses `intl` rather than hand-rolled format patterns. Problem-code narratives
are catalog keys, with a generic localized fallback for unknown codes;
backend `detail` and raw exception text are never displayed.

## Alternatives considered

### `slang`

Rejected. It offers convenient context-free access, but introduces a
third-party dependency and a non-standard message format. The repository
already favors official, generated contracts where the SDK provides them.

### `easy_localization`

Rejected. Runtime string keys allow missing or misspelled messages to survive
until execution and provide no useful compile-time catalog safety.

### Dart Fluent port (`fluent` / `fluent_flutter`)

Rejected. It would mirror backend syntax, but the client must not share the
backend message layer: client copy is selected by problem code and may contain
title/body/CTA narratives. Runtime parsing would also lose the CI compile-time
key gate and add community package supply-chain risk.

## Consequences

- Translation work has a standard ARB/TMS-friendly format and CI can reject
  incomplete or drifted catalogs.
- German copy can be validated as the canonical shipped language, while
  English remains complete rather than silently falling back.
- Controllers need an explicit locale/catalog dependency for narrative
  construction; this is intentionally observable rather than hidden.
- Generated localization files and the ARB catalogs become review and CI
  artifacts. Any generated output change must come from `flutter gen-l10n`.
- Additional locales require a new ARB file and supported-locale decision;
  this change intentionally supports only German and English.

## Verification

The change must run `flutter gen-l10n`, compare ARB key sets, parse the
`untranslated-messages-file` report (an empty JSON object passes), and diff
all generated Dart output against the committed tree. German and English
widget tests cover at least one screen and the seasons screen remains
layout-resilient to expanded translations.
