# Error Localization

## Purpose

Provides server-side localization of the problem `detail` member using Mozilla Fluent bundles embedded in the API binary. `Accept-Language` negotiation is q-value aware with a configured fallback chain (`requested* → de → en`); German is the default. Message keys derive 1:1 from registry codes, a CI bundle-coverage lint prevents drift, and message arguments come only from whitelisted S0/S1 extension fields.

## Requirements


### Requirement: Server-side localized `detail` via Fluent

The `detail` member of every problem response SHALL be localized server-side
using Mozilla Fluent (`fluent-bundle`) message bundles embedded in the API
binary. The `title` member SHALL be a constant English string per code.
Localization SHALL support CLDR plural and gender categories (Fluent
`select` expressions) so that future locales with complex plural rules
(e.g. `pl`, `uk`) require no code change.

#### Scenario: German client receives German detail
- **WHEN** a request carrying `Accept-Language: de` fails with code `scene.already-scheduled`
- **THEN** `detail` SHALL be the German message from the `de` bundle
- **AND** `title` SHALL be the constant English title for that code

#### Scenario: Plural-aware message for complex-plural locale
- **WHEN** a future code has a plural-sensitive message and the negotiated locale is Polish or Ukrainian
- **THEN** the Fluent `select` expression SHALL choose the CLDR-correct plural category without any Rust code change

### Requirement: Accept-Language negotiation with q-value awareness

Locale selection SHALL parse the `Accept-Language` header including quality
values and SHALL attempt locales in client preference order against the
supported set, falling back through the configured chain `requested* → de →
en`. German (`de`) SHALL be the default when the header is absent, empty, or
matches nothing.

#### Scenario: q-values are honoured
- **WHEN** a request carries `Accept-Language: uk, en;q=0.2, de;q=0.9`
- **AND** `uk` is not yet a supported locale
- **THEN** the response `detail` SHALL be German (q=0.9 wins over en at 0.2), falling back only within the supported set

#### Scenario: Missing header defaults to German
- **WHEN** a request fails without an `Accept-Language` header
- **THEN** `detail` SHALL be German

### Requirement: Code-to-message-key identity and bundle coverage

The problem `code` SHALL map 1:1 to its Fluent message key by deterministic
transformation (e.g. `scene.already-scheduled` → key for that code in every
bundle). A CI lint SHALL fail the build when the registry contains a code
without a message in any *active* locale (initially `de`, `en`) or when a
bundle defines a key absent from the registry.

#### Scenario: New code without messages fails CI
- **WHEN** a developer registers a new problem code but forgets the `en` message
- **THEN** the bundle-coverage lint SHALL fail CI, naming the code and the missing locale

#### Scenario: Orphan message key fails CI
- **WHEN** a bundle contains a message key with no corresponding registry code
- **THEN** the lint SHALL fail CI, preventing drift after code deprecation

### Requirement: Message parameters drawn only from whitelisted extensions

Fluent message arguments SHALL be populated exclusively from the code's
declared S0/S1 extension fields (typed values, escaped by Fluent's variable
interpolation — never by string concatenation). S2-classified data SHALL NOT
be passed as message arguments.

#### Scenario: Extension value appears in translated sentence
- **WHEN** the German message for `scene.already-scheduled` references the conflicting shooting day and the problem carries `offending_shooting_day_id`
- **THEN** `detail` SHALL contain that value rendered through Fluent interpolation with proper escaping, with no `format!`-style string building at the HTTP layer

### Requirement: Bundle layout ready for translation-platform import

Fluent bundle files SHALL live under a single directory in the repository
(e.g. `crates/api/locales/<lang>/errors.ftl`), one file (or a small fixed set)
per locale, using only standard Fluent syntax, so that Pontoon/Weblate can
import the tree without restructuring when the third locale is added.

#### Scenario: Adding a locale is a tree-only change
- **WHEN** a translator adds `locales/fr/errors.ftl` covering every registry code and `fr` is added to the supported-locale configuration
- **THEN** French problems SHALL be served without any further Rust changes

