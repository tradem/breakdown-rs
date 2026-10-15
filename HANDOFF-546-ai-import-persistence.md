<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Übergabeprompt — Issue #546, dritter PR: AI-Import-Persistence (§5.8) + Abschluss

Starte in `/home/digiwitcher/Projekte/repos/breakdown-rs`.

## 0. Vertrauensregel

Dieser Prompt beschreibt geprüfte Fakten zum Zeitpunkt der Erstellung (alle
Datei-/Zeilen-Referenzen wurden gegen `origin/main` verifiziert), aber
**prüfe vor jeder Änderung selbst nach** (`git log`, `gh pr view`, `gh issue
view 546`, `openspec list`). Wenn eine Aussage hier und die Realität
divergieren: **Realität gewinnt**, und sag dem User, was abweicht.

## 1. Ziel

**Issue #546 vollständig abschließen.** Nach diesem PR sind alle
Acceptance-Checkboxen des Issues erfüllt (auch §5.8), der OpenSpec-Change
`546-scene-costume-assignment` wird archiviert und das Issue geschlossen.
Der PR-Body trägt deshalb zu Recht **`Closes #546`**.

## 2. Ausgangslage (Stand bei Erstellung, alles gegen `origin/main` verifiziert)

- **PR #578** (`feat(scene): ordered costume beats…`) ist **MERGED**:
  `SceneAggregate.costume_beats` + 4 Routen + `SceneView.costumeBeats`
  + Projektor mit `guard_parent`-Version-Fence
  (`backend/crates/infra/src/projectors/scene.rs:343-376`).
- **PR #579** (`feat(flutter): scene costume beats UI…`) ist OPEN:
  Flutter-UI (tasks 5.1–5.4). **Voraussetzung zum Start: #579 MERGED** (oder
  der User bestätigt den Merge) — dieser PR hier berührt es nicht, aber
  `tasks.md` wird geschlossen und archiviert, also erst den UI-PR rein.
- **PR #551** (`feat(ai-import): apply extracted figures and costumes…`)
  ist **MERGED** (2026-09-28): der Apply-Worker legt Szenen, Figuren und
  Kostüme an — **aber genau dort endet es**. Verifiziert:
  - `AssignCharacter` wird im `ai`-Modul **nie** dispatched (nur der
    Test-Double-Stub, `backend/crates/infra/src/ai/tests.rs:919-921`).
  - `AddCostumeBeat` existiert im Worker nicht.
  - `mapping_kind` kennt nur `SCENE`/`CHARACTER`/`COSTUME`/`SHOOTING_DAY`/
    `SCENE_SHOOT` (`backend/crates/core/src/ai/ports.rs:441-446`) — kein
    `SCENE_COSTUME_BEAT`. Das Modul dokumentiert neue Kinds als **additiv**.
  - Der Worker macht pro Kostüm-Zeile `CreateCostume → UpdateCostumeNotes →
    AssignCostumeToCharacter` mit `CostumePhases`
    (`backend/crates/infra/src/ai/workers.rs:795-808`, Dispatch ~1318-1394)
    als Crash-Recovery-Phasenprotokoll — **das ist das Vorbild** für die
    Szenenkette.
  - Die Extraktion liefert bereits alles Nötige:
    `CostumeApplyPlan { ordinal, character_identity, character_name,
    description, source_quote }`
    (`backend/crates/core/src/ai/preview.rs:432-446`). Die `costumes`-Liste
    einer Row ist **flach über alle Figuren** — `ordinal` ist eine
    Per-Szenen-Position, kein Per-Figure-Index. Ein `unapplied_costumes`
    Drop-Pfad existiert (`preview.rs:469`).
- **`ai-import-character-costumes` ist ARCHIVIERT**
  (`openspec/changes/archive/2026-09-28-ai-import-character-costumes/`) —
  der Three-Way-Delta-Konflikt aus Issue §5.8 ist damit entschärft. **Aber:**
  der Hauptspez `openspec/specs/costume-character-binding/spec.md:14`
  trägt weiterhin den Satz *„the import path SHALL NOT introduce a season,
  episode or scene scope on the Costume"*. Er wird durch das Archivieren des
  546-Changes (dessen Delta `costume-character-binding` MODIFIZIERT)
  korrigiert — **das gehört zwingend in diesen PR** (siehe §3).
- **tasks.md des offenen Changes** `openspec/changes/546-scene-costume-assignment/`
  hat genau **eine** offene Checkbox: **2.5 Infra-Tests** (Projektor-Tests
  für alle vier Beat-Events inkl. Version-Guard-Redelivery; Migration
  up/down; FK-Cascade). PR #578 hat die `guard_parent`-Logik geliefert,
  aber die dedizierten Infra-Tests fehlen (verifiziert: keine
  Beat-spezifischen Redelivery-/Migrations-Tests unter
  `backend/crates/infra/`).
- Der gepinnte Arithmetik-Test existiert als Vorbild:
  `test_ai_apply_chain_advances_exactly_one_version_per_step`
  (`backend/crates/core/tests/costume_aggregate.rs:885`).
- **Die Szenenkette braucht einen geteilten Versionszähler:** eine
  `SCENE`-Mapping-Row und die neuen `SCENE_COSTUME_BEAT`-Rows halten
  Versionen **desselben Streams** (Szenen-Aggregat). Kette:
  `CreateScene → AssignCharacter×n → AddCostumeBeat×m`, ein Event pro
  Schritt, „only moves forward"-Confirm wie bei `CostumePhases`
  (`workers.rs:1400-1418` — Version dort nachprüfen).

## 3. Scope dieses PRs

### 3.1 OpenSpec (zuerst — der Code folgt der Spezifikation)

Im **offenen Change** `546-scene-costume-assignment`:
- **Neues Delta `specs/ai-import/spec.md`** (MODIFIED Requirements): der
  Apply-Pfad persistiert die Szenen-Beziehung — pro Draft-Row `AssignCharacter`
  je Figur **vor** den Beats, `AddCostumeBeat` je Kostüm in Plan-Reihenfolge,
  `SCENE_COSTUME_BEAT`-Mapping-Rows; Re-Apply fügt keinen zweiten Beat hinzu;
  der Reviewer-Report trennt „dropped as ungrounded" von „applied as a beat".
  (Der 546-Change hat heute kein ai-import-Delta — verifiziert. Das Issue
  nennt das ai-import-Delta als *optional*; mit §5.8 in diesem PR ist es
  Pflicht.)
- **Offene Checkbox 2.5 abarbeiten und abhaken.**
- Eigene Task-Sektion für §5.8 ergänzen (z. B. „§6 AI-import persistence")
  und die neuen Aufgaben dort tracken; `openspec validate
  546-scene-costume-assignment --strict` bleibt grün.
- **Archivieren erst NACH dem Merge dieses PRs** (siehe §5): `openspec
  archive 546-scene-costume-assignment` — dabei wird u. a. der
  „SHALL NOT introduce … scene scope"-Satz im Hauptspez korrigiert.

### 3.2 Core (`backend/crates/core/`)

- **`mapping_kind::SCENE_COSTUME_BEAT`** in `ports.rs` (additive Konstante,
  Doc-Zeile mit Issue-Referenz).
- **Pure Re-Grouping-Funktion** (Plan → Beats): filtere die flache
  `costumes`-Liste der Row nach `character_identity`, behalte Plan-Order,
  nummeriere je Figur `0..n-1`. Kein neues Extraction-Verhalten, kein
  LLM-Call. Unit-getestet (leere Liste, zwei Figuren, Drop einer Figur die
  nicht in der Row steht → `unapplied`).
- **Drop-Regel-Unterscheidung:** der Reviewer-Report muss „dropped as
  ungrounded" (`unapplied_costumes`, `preview.rs:469`) von „applied as a
  beat" trennen — ein fehlendes Kostüm und eine fehlende Szenen-Relation
  dürfen im Report nicht identisch aussehen. Erweiterung von
  `UnappliedCostume`/Report-Struct ist additiv.

### 3.3 Infra / Apply-Worker (`backend/crates/infra/src/ai/`)

Vorlage ist `CostumePhases` (workers.rs:795-808). Pro Draft-Row, **nach**
dem bestehenden `CreateScene`-Schritt:
1. **`AssignCharacter` je Figur der Row, vor den Beats** (Invariant I1: ein
   Beat existiert nur für eine Figur in `assigned_characters`; der Handler
   antwortet sonst 422 `scene.character-not-in-scene`).
2. **`AddCostumeBeat` je Kostüm** in der per-Figur-Re-Gruppierung aus 3.2.
3. **Phasen-Protokoll `ScenePhases`** (analog `CostumePhases`): Mapping-Rows
   `SCENE_COSTUME_BEAT`, Key `(preview_id, draft_ref, SCENE_COSTUME_BEAT,
   per-figure-order)`, `aggregate_id` = Szenen-ID. Die Szenen-Stream-Version
   wird **gemeinsam** über die `SCENE`-Row und die Beat-Rows geführt;
   `confirm` behält „only moves forward" (`workers.rs:1400-1418`); die
   Chain führt genau ein Event pro Schritt.
4. **Mapping-Kollision dokumentieren:** eine `SCENE`-Row und eine
   `SCENE_COSTUME_BEAT`-Row halten Versionen desselben Streams — schreibe
   die Konsequenz (wieder auflesen = max beider Versionen lesen) in die
   Doku des Workers/der Rows.

### 3.4 Tests (der Kern des PRs)

- **Gepinnte Arithmetik** analog
  `test_ai_apply_chain_advances_exactly_one_version_per_step`
  (costume_aggregate.rs:885): die Szenenkette
  `CreateScene → AssignCharacter×n → AddCostumeBeat×m` hängt **genau ein
  Event pro Schritt** an.
- **Re-Apply:** eine wiederholte Row hängt **keinen zweiten Beat** an
  (Idempotenz über die Mapping-Rows).
- **Crash-Recovery:** ein Abbruch zwischen den Schichten resümiert an der
  richtigen Phase (Version-Confirm je Schritt).
- **Drop vs. Beat:** Report unterscheidet beide Fälle.
- **2.5 Infra-Tests** (tasks.md): Projektor für alle vier Beat-Events inkl.
  Version-Guard-Redelivery (`guard_parent`), Migration up/down,
  FK-Cascade beim Löschen der Szenen-Row.
- Backend-Testsuiten: `cargo test -p breakdown-core -p breakdown-infra`,
  plus `cargo mutants` nur falls der CI-Gate es verlangt (Konvention von
  PR #578 nachprüfen).

## 4. Explizit NICHT in diesem PR

- **Keine neue Extraktion / kein LLM-Work** (§5.8 ist Persistenz, nicht
  Extraktion; Schedule-Import-Costuming bleibt separater Proposal).
- **Keine Flutter-Änderungen** (UI ist mit #579 abgeschlossen; prüfe aber,
  ob der Reviewer-Report im Flutter-Import-Job-View neue Felder zeigen will
  — falls ja: separater Mini-PR, nicht hier reinmischen).
- **Keine Änderung an den vier Szenen-Routen oder dem Aggregat** — #578 ist
  fertig; der Worker konsumiert nur.

## 5. Workflow-Vorgaben

- **Branch:** `feature/546-ai-import-persistence` von `main` (nach Merge
  von #579).
- **PR-Body:** `Closes #546` (jetzt legitim), Verweise auf #578, #579, #551
  und US-4.3 (#14); Version-Bump-Tabelle mit expliziten `none`-Zeilen für
  `core`/`infra`/`api`/`frontend-flutter`, falls nichts gebumpt wird
  (Konvention von PR #578 prüfen — Backend-Bumps sind dort `none`).
- Conventional Commit (`feat(ai-import): … (issue #546)`), Co-authored-by
  aus `$PI_MODEL`/`$PI_PROVIDER`, append-only in vorhandenen Headern.
- CodeRabbit-Review erwartet: 1:1 threaded replies mit
  `Fixed:`/`Deferred:`/`Not applicable:`-Präfix (Skill `coderabbitai-review`).
- **Nach dem Merge dieses PRs (Abschluss-Schritte, direkt danach ausführen):**
  1. `openspec archive 546-scene-costume-assignment` — prüfe im Diff, dass
     der „SHALL NOT introduce a … scene scope"-Satz korrekt neu formuliert
     ist (das 546-Delta `costume-character-binding` ist die Quelle).
  2. Issue #546 schließt automatisch (`Closes`); verifiziere, dass alle
     Acceptance-Checkboxen im Issue abgehakt sind (manuell nachhaken, die
     Issue-Checkboxen toggelt ein Mensch oder ein Skript — der Merge tut
     es nicht).

## 6. Validierung vor dem PR

```bash
cd backend
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p breakdown-core -p breakdown-infra
UPDATE_OPENAPI=1 ./scripts/openapi_drift   # nur falls openapi.yaml angerührt wird — soll er nicht

cd ..
openspec validate 546-scene-costume-assignment --strict
bash scripts/check-design-diagrams.sh      # unverändert grün
```

Flutter/Vendor wird **nicht** angerührt — `vendor/breakdown_api` bleibt
byte-identisch (rebuild-only, kein Regenerieren nötig, kein Wire-Change).
