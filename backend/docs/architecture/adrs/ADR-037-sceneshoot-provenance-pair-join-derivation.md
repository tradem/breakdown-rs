<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# ADR-037: SceneShoot AI Provenance — Derive via the Pair Join, No First-Class Field

**Status**: Accepted
**Date**: 2026-10-07
**Author**: Tobias Rademacher (@tradem); glm-5.3-flash (opencode-go)
**Related**: ADR-030 (AI Import Bounded Context), ADR-031 (HTTP Error Surface), ADR-036 (ES-native Reservation Streams)
**Source change**: tracked in GitHub issue #539 (follow-up to #517, decision recorded in `openspec/changes/539-sceneshoot-provenance-decision/`)

---

## Context

The #517 backend change (EU AI Act Art. 4/50 transparency) added a first-class
AI provenance discriminator to the `ShootingDay` aggregate
(`ShootingDaySource::Manual | AiExtracted { document_id, external_ref,
confidence }`) and to the `Scene` aggregate (`SceneSource`, same shape) — as
an additive event field with a serde default, a JSONB projection column
(`20260926000001_projection_scene_source.up.sql`), an OpenAPI update and a
regenerated Dart client.

`SceneShoot` — the aggregate modelling the association between a `Scene` and
a `ShootingDay` (one stream per `(scene_id, shooting_day_id)` pair) — got no
source field in that change. The #517 review deliberately deferred the
question to issue #539: is a first-class provenance field on `SceneShoot`
needed, or is its provenance transitively implied?

Key facts that shape the decision:

- **The pair is immutable.** `(scene_id, shooting_day_id)` is the stream
  identity of a `SceneShoot`; it is set once by `PlanSceneShoot` and never
  mutated (pair-uniqueness enforced, no re-association command exists).
- **Scene provenance is immutable.** `SceneCreated.source` is set once at
  creation; there is no "update source" event, so a scene's provenance never
  changes after the fact.
- **Both pair partners carry provenance today.** The scene and the shooting
  day of any SceneShoot pair are provenance-carrying aggregates as of #517.
- **No read surface needs SceneShoot provenance yet.** The `DispoRow` /
  `ShootDayRow` report rows carry no provenance today; the Flutter day board
  badges the *day* (AppBar), the scene list badges the *scene*. A future
  per-row badge is conceivable (Dispo rows, Soll-Ist-Vergleich) but is not
  requested by any current requirement.
- **The report queries already join the scene projection.**
  `dispo_report` / `shoot_day_report` join `projection_scene` for
  `scene_number`, `script_day`, `location`, `mood`, `summary` — a future
  provenance column is one added select column on an existing join, not a
  new join chain or a duplicated read-side lookup.
- **Audit attribution of the planning act is intentionally human.** The AI
  import apply dispatches `PlanSceneShoot` with the human reviewer's actor
  (`Provenance::Human`); `projection_audit` therefore proves the *reviewer*,
  not the model. The authoritative content provenance lives first-class on
  the scene; the import batch remains reconstructable via
  `ai_import.projection_ai_import_mapping` and the job records.
- **EU AI Act (Regulation (EU) 2024/1689) reading.** The deployer duties the
  app answers to (Art. 50(1) interaction-point disclosure, permanent marking
  of AI-derived results in read surfaces, human review before effect) are
  satisfied by the #517 disclosures, the scene/day provenance badges, and
  the preview→apply review step. Art. 50(2) machine-readable marking of raw
  model outputs rests with the provider, not the deployer. None of these
  duties requires per-row planner attribution ("the model planned this
  shoot row") on internal report rows.

## Decision

**SceneShoot provenance is derived via the pair join — no first-class
`source` field is added to the aggregate, its events, the projection, the
API surface, or the Dart client.** Authoritatively:

> The provenance of a `SceneShoot` is the provenance of its **scene**
> (`SceneCreated.source`). A reader that needs a provenance badge on a
> SceneShoot-level row joins `projection_scene.source` via the (immutable)
> `scene_id` of the pair.

Concretely:

1. **No domain change.** `SceneShootEvent` variants, `SceneShootAggregate`
   state, and the `PlanSceneShoot` command stay as they are.
2. **No projection change.** No new column, no migration, no projector
   branch, no OpenAPI/Dart regeneration.
3. **Future read surfaces derive, they do not duplicate.** When a
   SceneShoot-level surface first needs a provenance badge (e.g. a Dispo
   row), the query adds the scene's provenance to the already-existing
   `projection_scene` join and exposes it as derived data. Read-side
   derivations may be added without a new ADR; they must not write a
   duplicated provenance fact back into any projection.
4. **Forensic questions route through the audit layer, not the domain.**
   "Was this shoot row created by the AI import?" is answered by
   correlating the import job / `ai_import.projection_ai_import_mapping`
   records with the event streams — the same reconstruction the #517 scene
   migration comment documents. The audit records the human reviewer
   (that attribution is correct and intended: the reviewer is the person
   who took editorial responsibility for the apply).

## Consequences

### Positive

- **Zero migration/compat cost.** No serde default, no projector branch, no
  JSONB backfill question, no OpenAPI drift, no Dart/Drift regeneration.
- **No drift risk.** A duplicated `source` on SceneShoot could diverge from
  the scene's truth; the derivation cannot — both inputs are immutable.
- **Clean semantics.** The badge always answers "is this *content*
  AI-extracted", which is a property of the scene — not of the shoot row
  that happens to schedule it.
- **Future badge is cheap.** One select column on a join that already
  exists in every report query.

### Negative

- **The "who planned this shoot row" question stays non-attributable at the
  row level.** Import-apply vs. manual planning of a SceneShoot is only
  reconstructable forensically (job/mapping correlation), never by reading
  a single projection row. Accepted: no current or foreseeable requirement
  asks that question, and the audit's human-reviewer attribution is the
  intended accountability model.
- **Mixed-provenance scheduling is unnamed.** A manually created scene
  planned onto an AI-imported day (or vice versa) has no single label at
  the shoot level; consumers must decide per surface whether to show the
  scene's or the day's provenance. Accepted: this ambiguity exists in the
  domain itself and duplicating a field would only hide it behind an
  arbitrary resolution rule.

## Alternatives Considered

1. **Additive `source` discriminator (Option B, the #517 pattern).** Add
   `SceneShootSource` to `SceneShootPlanned` (serde default `Manual`),
   projector + JSONB migration with `Manual` default for legacy rows,
   queries, OpenAPI, Dart regen, Drift cache migration. **Not chosen:** it
   duplicates an authoritative fact that already lives on the scene, adds a
   drift/divergence question (which provenance wins for a manual scene on
   an AI day?) with no principled answer, and buys a distinction ("the
   import planned this row") that no requirement asks for — the AI apply
   dispatches under the human reviewer by design. **This option remains
   open** as the only-opening case: if a future requirement genuinely needs
   first-class row-level planner provenance, it should be implemented then,
   per the #517 pattern, with an explicit semantic decision for the
   mixed-provenance case.
2. **Derive from the shooting day instead of the scene.** The pair's second
   half also carries provenance. Not chosen as the *authoritative*
   derivation target: the day's provenance describes the *document context*
   the schedule was extracted from, while a badge on a shoot row should
   answer content provenance (the scene). Both are derivable; if a surface
   needs the day's variant it can join it the same way — the decision
   pins only that shoot-level surfaces *derive* rather than *duplicate*.

## Notes

- The pair-join derivation relies on both immutability facts above; if a
  future change ever introduces scene re-parenting (mutable `scene_id` on a
  SceneShoot) or a "scene provenance update" event, this ADR must be
  revisited before any consumer relies on the derivation.
- The #517 scene migration comment documents the same audit-reconstruction
  stance for the legacy-row backfill question (`projection_audit` proves
  nothing about the model because the apply is dispatched with the human
  actor).
- Version-bump table: none (docs-only decision record; no crate API
  touched).
