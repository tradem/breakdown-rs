<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Flutter App Foundation — Android-first `AGENTS.md` and Operating Constitution

## Why

`backend/AGENTS.md` codifies ADRs 001–031 into operating rules for the Rust
service. The Flutter counterpart does not exist yet. ADR-007 already decides
*what* the frontend is (Flutter for mobile, OpenAPI-generated Dart client,
CQRS-aware client) and its "Next Steps" explicitly call for "Document frontend
patterns in `AGENTS.md`." This change lands that document — as `design.md`
here and as a sibling `frontend-flutter/AGENTS.md` on disk — before any
Flutter screen is written, so screen-by-screen development inherits fixed
quality conventions rather than improvising them.

Android is the first target; macOS is explicitly later. The web/desktop path
(SvelteKit, `frontend-web/`) is out of scope for this change.

## What changes

1. **New directory `frontend-flutter/`** in the monorepo root, containing
   `AGENTS.md` (the operating constitution) plus the conventions for the
   future scaffold (`pubspec.yaml`, `lib/` tree, generated-client folder,
   `.pi/skills/`).
2. **OpenSpec captures the design** — this change's `design.md` *is* the
   `AGENTS.md` content; the on-disk `frontend-flutter/AGENTS.md` is created
   from it during the foundation apply step (Task 1.2) and kept
   byte-identical thereafter.
3. **Locked decisions** (see §Decisions) are recorded as delta specs under
   `specs/` so they are first-class, reviewable requirements rather than
   prose buried in a manual.
4. **Open questions** (§Open questions) are resolved while drafting
   `design.md` and folded back into the specs.

## Decisions already locked (during explore)

These were pressure-tested against the actual domain (the production
hierarchy, the auth-gated continuity-photo capture flow, projector-lag
reconciliation) before this proposal was opened:

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Flutter + OpenAPI-generated Dart client** (ADR-007) | Already accepted; no change. |
| D2 | **Resource-REST CQRS client, not a "command-bus" client** | The checked-in `backend/openapi.yaml` is resource-oriented; corrects the stylized `POST /commands/{aggregate}/{action}` sketch in ADR-007 (flag a small ADR amendment separately). |
| D3 | **Riverpod + `riverpod_generator`** for state management / DI | Compile-safe test seams (`override`), best widget-test velocity, ecosystem traction; accepts it *is* a framework, bending the backend's "no DI framework" ethos. `fpdart` `Result` keeps the no-throw discipline. |
| D4 | **Test pyramid: unit → widget → integration_test (+ optional golden)** | Mirrors backend pyramid shape; mutator tier is a known gap (see D5). |
| D5 | **No mutation-testing gate for Flutter** | No maintained Dart/Flutter mutator exists (known gap). Compensate with: `coverde` line+branch threshold on changed code, golden tests, explicit Err-branch assertions on every `Result`, semantic-finder widget tests. Revisit if a maintained mutator emerges. |
| D6 | **AUTHZ-GATE pattern ported to the client** | Every screen route gated by auth state; gated photo/binary calls run a client-side role check via a `currentMembershipProvider` before hitting the network, mirroring backend handler-internal authz. |
| D7 | **SPDX headers + co-authored-by on `.dart`/`.feature`/`.yaml`** | Same licensing discipline as the backend. |
| D8 | **CI: `dart format`/`flutter analyze`/`flutter test`/OpenAPI-client drift/gitleaks/SHA-pinned actions** | Mirrors backend CI gate shape; OpenAPI drift check is the analog of `UPDATE_OPENAPI=1 ... openapi_drift`. |

## Open questions (to resolve in `design.md`)

Each of these changes scope or depth of the AGENTS.md; they will be decided one
at a time before `design.md` is finalised and recorded as specs:

| # | Question | Options under consideration |
|---|----------|------------------------------|
| ~~Q1~~ | **Offline support scope** | ✅ **Resolved → (b) Read-Cache only.** Online-first commands (no offline queue); read projections cached in Drift for fast boot + brief offline reads. Offline *writes* deferred. See `specs/flutter-offline-scope/`. |
| ~~Q2~~ | **Gherkin BDD** | ✅ **Resolved → (c) Hybrid.** Gherkin `.feature` files under `features-spec/` for business-critical acceptance scenarios only (Soll-Ist, continuity-photo capture w/ AUTHZ-GATE, costume assignment); everything else via widget/integration tests. See `specs/flutter-gherkin-hybrid/`. |
| ~~Q3~~ | **OpenSpec home for Flutter specs** | ✅ **Resolved → (c) Monorepo-root `/openspec/`.** Single canonical OpenSpec root at `breakdown-rs/openspec/`; backend + flutter + future frontends are sibling capabilities. Migration of existing `backend/openspec/**` is a separate follow-up change (`migrate-openspec-to-monorepo-root`); this change's artifacts stay at their created location until then. See `specs/flutter-openspec-home/`. |
| ~~Q4~~ | **`flutter/genui` as a drafting tool** | ✅ **Resolved → (b) defer-ban (lean toward c).** Not adopted as a prescribed workflow; `ConsumerWidget`+Riverpod+`Result` conventions make genui output an 80%+ rewrite, and a spec-aware coding assistant strictly beats genui-as-intermediate. Re-evaluation possible only with reliable Android-fleet Nano + constrained-to-conventions tooling; recurring misuse triggers an upgrade to a hard ban. See `specs/flutter-genui-policy/`. |

## Non-goals

- **No Flutter code or scaffold is written in this change** — `AGENTS.md` and
  `design.md` capture thinking; the actual `flutter create` scaffold, first
  screen, and ported skills are separate implementation changes that will
  reference this proposal.
- **No macOS-specific build configuration** (Android-first; macOS deferred).
- **No SvelteKit / `frontend-web/` work** — out of scope.
- **No backend changes** (the OpenAPI spec, problem-code surface, and auth
  surface are assumed stable as-is).
- **No ADR-007 amendment in this change** — the resource-REST correction is
  noted in `design.md` and flagged for a follow-up ADR edit if warranted.

## Impact

- Adds a new top-level monorepo directory `frontend-flutter/`.
- Adds reviewable OpenSpec specs that future Flutter implementation changes
  must conform to.
- Does not touch `backend/`, `frontend-web/`, CI workflows, or OpenAPI output.
