# flutter-genui-policy Specification

## Purpose
TBD - created by archiving change add-flutter-app-foundation. Update Purpose after archive.
## Requirements
### Requirement: genui Not Adopted as a Drafting Workflow
The Flutter app SHALL NOT adopt `flutter/genui` (Gemini-Nano on-device UI
generation) as a prescribed drafting workflow. Screen scaffolding is
performed directly against the locked conventions by the coding assistant /
developer (one opinionated pass: `ConsumerWidget` + Riverpod provider +
`Result`/`Either` + AUTHZ-GATE + generated OpenAPI client + Material 3 tokens).

> Rationale (cost/benefit): genui's value proposition is "fast first-cut
> widget tree for *default* Flutter idiom" (`StatefulWidget`, `setState`,
> inline `http`). This project's conventions are explicitly opinionated
> *against* that idiom — `StatefulWidget`+`setState` is rejected in favor of
> Riverpod providers, `http` is replaced by the generated typed client,
> `throw` paths become `Result` returns, and gated calls require a
> `// AUTHZ-GATE:` check. Under these conventions a genui output is an
> 80%+ rewrite, so the "starting point" value is negative: more effort to
> understand-and-rewrite than to author conventionally.
>
> A frontier coding assistant that has read the specs produces
> convention-conformant code in a single deterministic pass — strictly
> superior to genui-as-intermediate (Szenario B > Szenario C).
>
> Additional factor: on-device LLM availability on the Android fleet in the
> target user base (theater/costume staff) is unreliable today, and even
> for dev-only drafting it produces non-deterministic output that degrades
> review consistency.

#### Scenario: A screen is scaffolded without genui
- **WHEN** a contributor scaffolds a new screen.
- **THEN** it is authored directly as a `ConsumerWidget` + `@riverpod`
  provider + `Result`/`Either` + AUTHZ-GATE + generated OpenAPI client,
  with no `flutter/genui` intermediate step in the workflow.

### Requirement: Re-evaluation Path and Optional Future Ban
The decision is explicitly *defer-ban*, not *permanent-skip*. A future
change proposal MAY re-evaluate genui (or an equivalent on-device generation
tool) if and only if: (a) on-device LLM availability on the target Android
fleet becomes reliable, AND (b) tooling can be constrained to emit code
conforming to Riverpod + OpenAPI-client + Result discipline. Should a
contributor introduce genui outputs into review despite this requirement,
the reviewer challenges them — the prohibition is already normative
(`SHALL NOT`). If the pattern recurs, a hard-ban spec that adds mechanical
enforcement of that existing prohibition is the prescribed remedy.

> Encoding intent: the requirement above is already normative (`SHALL NOT`):
> genui output is not adopted today, full stop. What recurrence escalates is
> the *enforcement posture* — repeated misuse moves the rule from
> review-challenge to a hard, mechanically-checked ban. The current analysis
> favors Szenario B (assistant authors directly); if that path keeps producing
> quality screens with low review friction, the natural endpoint is that hard
> ban — hence "defer-ban" rather than "maybe-later".

#### Scenario: A PR ships genui-generated widget code
- **WHEN** a PR introduces a widget that a contributor authored via
  `flutter/genui` and lightly cleaned up.
- **THEN** review challenges it under this requirement; the contributor is
  asked to re-author the screen conventionally (ConsumerWidget + Riverpod
  provider), and the genui output is not merged as-is.

#### Scenario: A screen is scaffolded conventionally
- **WHEN** a contributor scaffolds a new screen.
- **THEN** it is authored directly as a `ConsumerWidget` + `@riverpod`
  provider + `Result`/`Either` + AUTHZ-GATE + generated OpenAPI client by
  the coding assistant / developer, with no `flutter/genui` intermediate
  step.

#### Scenario: A contributor proposes making genui a prescribed tool
- **WHEN** a change proposal is opened to upgrade genui to a recommended
  drafting workflow.
- **THEN** it must demonstrate both reliability conditions above
  (Android fleet coverage + constrained-to-conventions output); absent
  that evidence it is closed as superseded by this requirement.

