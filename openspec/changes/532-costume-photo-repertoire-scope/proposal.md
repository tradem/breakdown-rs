<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# 532 — Photo-Upload für unassigned-aber-im-Repertoire-Kostüme ermöglichen

## Why

Kette der Facts:

1. `CostumeCreated` trägt `season_id: Option<SeasonId>` (Repertoire-Staffel,
   eingeführt durch #453).
2. Der Costume-Projector schreibt sie nach `projection_costume_season`
   (Migration `20260216000001_costume_season_repertoire.up.sql`, PK
   `(costume_id, season_id)`).
3. **Der Flutter-Client legt jedes Kostüm mit Repertoire-Staffel an** —
   `costumes_controller.dart` → `repo.create(seasonId)`.
4. Die drei Photo-Handler schauten **nie** in die Repertoire, sondern
   ausschließlich über den Charakter (`backend/crates/api/src/handlers/mod.rs`,
   `upload`/`bytes`/`delete`).

Ergebnis: die Season steht in der Projektion, wurde aber nicht gelesen — ein
**Lookup-Versäumnis, kein Feature-Bau**. #513/PR #524 hat das mit einem
ehrlichen, aber nicht mehr richtigen **Client-Pre-Deny** überbrückt
(`photo.requires_character`, 403, null Netzwerkaufrufe).

## Fix — Variante A (ohne Vertrags- und ohne Event-Änderung)

Scopes eines Kostüms = Charakter-Saison **∪** Repertoire aus
`projection_costume_season`. Autorisiert wird, wenn
`has_active_costume_role_in_season` für **irgendeine** dieser Scopes `true`
liefert.

**Any-Semantik:** `projection_costume_season` ist m:n, ein Kostüm kann in
mehreren Staffeln im Repertoire stehen. Bei genau einer Repertoire-Staffel (der
Client-Fall) sind Any und „die eine" identisch; die Any-Regel ist also nur der
Randfall.

## Scope — Backend

- `CostumeRepository`-Port (`core/src/costume/ports.rs`): neue Read-Methode
  `repertoire_seasons(costume_id) -> Vec<SeasonId>`.
- `infra/src/queries/costume.rs`: eine Query gegen
  `projection_costume_season` (statisches SQL, deterministisch nach
  `season_id` sortiert).
- `api/src/handlers/mod.rs`: **ein** Helper `authorize_costume_photo`, der
  `costume_season_scopes` auflöst und den ANY-Check durchführt — derselbe
  Helper in allen drei Photo-Handlern. `series_id_for_costume` bekommt
  denselben Repertoire-Fallback (best-effort, blockiert nie).
- Fakes: `api/src/handlers/test_helpers.rs` und `api/tests/common/mod.rs`
  (`repertoire`-Map, `costume_role_by_season`-Pin für die Any-Semantik,
  seedbarer `FakePhotoStorage`).
- Wire-Tests in `crates/api/tests/handler_costume_scope.rs`: Upload/Bytes/
  Delete auf einem unassigned-aber-im-Repertoire-Kostüm → 201/200/204;
  Any-Semantik (Charakter-Saison verbietet, Repertoire erlaubt);
  Kostüm ohne jeden Scope weiterhin 422; Scopes vorhanden, keiner erlaubt →
  403.

## Scope — Client

- Pre-Deny aus #524 aufgelöst: der Server ist für Repertoire-Kostüme jetzt
  **autoritativ und erfolgreich**. `uploadPhoto`/`deletePhoto` prüfen nur noch
  die Membership-Capability (AUTHZ-GATE bleibt), nicht mehr die
  Zeichen-Zuordnung.
- Die ehrliche Copy aus #524 (`costumeCommandErrorCopy` / `photoErrorCopy`,
  `photo.requires_character`) **bleibt unverändert** — sie ist der Fallback,
  wenn der Server doch ablehnt.
- `_PhotosSection` blendet die Capture-/Delete-Affordances nicht mehr aus und
  zeigt keine Gate-Narrative mehr; der `photo-assignment-gate-narrative`-Key
  entfällt.
- Die 4 #524-Tests des Foto-Gates werden auf das neue Verhalten umgestellt
  (Request wird abgesetzt) + ein neuer Err-Branch-Test: Server lehnt mit
  `domain.validation` ab → die Photo-Copy rendert (nie der
  „Kostüm konnte nicht gespeichert"-Fallback).

## Design-Constraint (bewusste Grenze)

Diese Lösung ist **absichtlich minimal** und nimmt der 0.4.x-Serie nichts
vorweg:

- **Keine** Migration, **kein** neues Event, **kein** neues Prädikat, **keine**
  Autorisierungs-Grenzverschiebung.
- **Kein** `season_id`-Feld auf `CostumeView` — der Client braucht es nicht, der
  Staffel-Kontext ist der Route-Parameter. Genau das hält
  `backend/openapi.yaml` und `vendor/breakdown_api/` unangetastet (kein
  Drift-Gate-Trigger, keine Client-Generierung).
- Der Helper ist der **eine** Seam, an dem die 0.4.x-Serie ansetzt. Ist er
  container-neutral benannt und in allen drei Handlern verwendet, wird später
  **eine Funktion** angefasst statt dreier Handler plus Port plus Policy.
- Der Helper bleibt **API-Edge** — er liest Projektionen. Das ist laut
  CQRS-Boundary-Hard-Rule der einzige legitime Read-Model-Konsument; der
  `cqrs-boundary`-CI-Job scant ohnehin nur
  `infra/src/{event_store,sagas,photo/sagas}` und ist vom API-Crate nicht
  betroffen. Der bisherige 422 verletzte sogar die Regel „audit metadata must
  never block command processing" — diese Änderung ist regelkonform.

## Abhängigkeiten

- #513 (PR #524) — die Client-Gate-Entscheidung, die hier korrigiert wird
- #453 — liefert die Repertoire-Daten, auf denen der Fix aufsetzt

## Cross-links / Nachfolge

- 0.4.x-Serie: #531 (ADR, begründend) → #533 (Staffel-Lifecycle) → #534
  (Repertoire-ES) → #535 (Authz auf Series-Ebene)
- Die Reads dieses Issues werden in #534 in die endgültige Form überführt; #535
  setzt am Helper an, den dieses Issue einführt.
