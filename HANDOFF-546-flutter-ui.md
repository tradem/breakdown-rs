<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Übergabeprompt — Issue #546, zweiter PR: Flutter-UI für Szenen-Kostüm-Beats

Starte in `/home/digiwitcher/Projekte/repos/breakdown-rs`.

## 0. Vertrauensregel

Dieser Prompt beschreibt geprüfte Fakten zum Zeitpunkt der Erstellung, aber
**prüfe vor jeder Änderung selbst nach** (`git log`, `git status`, `gh pr view`,
`gh api`). Wenn eine Aussage hier und die Realität divergieren: **Realität
gewinnt**, und sag dem User, was abweicht.

## 1. Ausgangslage (Stand bei Erstellung)

- **PR #578** (`feature/546-scene-costume-beats`) implementiert das **Backend**
  von Issue #546 und wartet auf Merge nach `main`:
  - `SceneAggregate.costume_beats` (ordered `SceneCostumeBeat
    { character_id, costume_id, order, note }`, dense zero-based per
    character, aggregate-computed).
  - 4 Routen (Block-Membership-Middleware gilt, kein Client-Sonderweg):
    - `POST /v1/scenes/{id}/costumes` — Body
      `AddSceneCostumeBeatRequest { character_id, costume_id, note, version }`
      (**kein** `order` — das Aggregat berechnet ihn)
    - `PATCH /v1/scenes/{id}/costumes/{character_id}/{order}` — Body
      `UpdateSceneCostumeBeatRequest { costume_id, note, version }`
    - `DELETE /v1/scenes/{id}/costumes/{character_id}/{order}` +
      `?version=N` (Query)
    - `DELETE /v1/scenes/{id}/costumes/{character_id}` + `?version=N`
      (Clear-all = „kein Kostüm in dieser Szene"; bei keinen Beats: 422
      `scene.beat-not-found`)
  - Alle Routen antworten 200 `AggregateVersion` (Echo für den
    Optimistic-Fence); 404 `scene.not-found`, 409
    `concurrency.version-mismatch`, 422 `scene.character-not-in-scene` /
    `scene.beat-not-found` / `scene.validation` (Identical-Beat-Guard).
  - `SceneView.costume_beats: Vec<SceneCostumeBeatView>` — Felder:
    `character_id, character_name?, costume_id, costume_category_id?,
    costume_category_name?, order, note?` (Enrichment best-effort,
    `null` bei Projection-Miss).
  - `RemoveCharacter` räumt Beats des Charakters **vor** dem Entfernen
    selbst auf (CodeRabbit-Fix in 7e90e363) — der Client muss dafür nichts.
- **Vendored Client** (`frontend-flutter/vendor/breakdown_api/`) enthält die
  Modelle bereits: `AddSceneCostumeBeatRequest`,
  `UpdateSceneCostumeBeatRequest`, `SceneView.costumeBeats`
  (`BuiltList<SceneCostumeBeatView>?`). **Nicht** neu generieren — er muss
  byte-identisch zum PR bleiben (rebuild-only).
- **App-Version** ist in PR #578 bereits auf `0.3.0-alpha.38+48` gebumpt
  worden. **Der Flutter-PR bumpt erneut: `0.3.0-alpha.39+49`.**
- **OpenSpec-Change** `openspec/changes/546-scene-costume-assignment/`:
  `tasks.md` §5 (5.1–5.4) ist der Restumfang dieses PRs — Arbeit die Liste
  ab, hake die Checkboxen ab. `openspec validate 546-scene-costume-assignment
  --strict` muss grün bleiben (delta specs ändern sich nur, wenn du Szenarien
  ergänzt).

## 2. Voraussetzung zum Start (hart)

1. `gh pr view 578 --json state,mergedAt` → **MERGED** (oder der User bestätigt
   den Merge). Vorher nicht starten — der Wire-Contract muss auf `main` sein.
2. `git checkout main && git pull`, sauberes Working Tree.
3. **`frontend-flutter/AGENTS.md` lesen, bevor Flutter-Code entsteht** (§1
   der Monorepo-Regeln; die Datei ist noch nicht im core/instructions-Split,
   gilt als Ganzes). Zusätzlich relevant: `openspec/specs/design-doc-workflow/
   spec.md` und `openspec/specs/flutter-state-management/spec.md`.
4. Branch: `feature/546-scene-costumes-ui`.

## 3. Scope dieses PRs (tasks.md §5.1–5.4)

### 3.1 Data-Layer + Controller (§5.1)

- `lib/data/scene_repository.dart`: `addCostumeBeat` /
  `updateCostumeBeat` / `removeCostumeBeat` /
  `clearCostumeBeats` — **`Result`-typisiert, kein `throw` in
  `data/`/`domain/`** (Frontend-Regel). Aufruf über den
  `HandlersApi` der vendored package.
- `lib/features/scenes/scenes_controller.dart`:
  - `// AUTHZ-GATE:`-Kommentar + **Membership-Capability-Check vor dem
    Netzwerkcall** (gleiche Sende- wie Lese-Story; siehe
    `CostumesController.addDetail`, `costumes_controller.dart:644-700`
    als Vorbild).
  - **Optimistic-after-2xx + Version-Fence + bounded-retry
    Reconciliation** — identisch zum Kostüm-Controller-Muster; der
    200-Body (`AggregateVersion`) wird zur neuen Szenen-Version.
  - `Err` → Command-Error-Banner, **keyed on `code`** (nicht `detail`):
    `scene.character-not-in-scene`, `scene.beat-not-found`,
    `scene.validation`, `concurrency.version-mismatch` mit lokalisierter
    ARB-Copy.

### 3.2 UI (§5.2)

- `lib/features/scenes/scene_detail_screen.dart`: neue
  **`_SceneCostumesSection`** als `ExpansionTile` (ein Muster wie
  `_SceneCharactersSection` — der Screen bleibt konsistent).
- **Ein Row pro (Character, Beat)**; mehrere Beats eines Charakters
  rendern `Kostüm A → Kostüm B`; `BreakdownMaterialIcons.forCostumeCategory
  (...)` neben jedem Kostüm (Icon-Regel aus #543/#545).
- Common case trivial halten: **Default ist eine Row pro Character.** Kein
  Sequence-Editor, kein Drag-and-Drop, keine Timeline.
- Empty State: zugewiesener Character **ohne** Beat zeigt inline
  „kein Kostüm in dieser Szene" + Öffnen des Pickers; Character mit Beats
  zeigt `+ Kostümwechsel` (Append weiterer Beat).
- Picker: `showModalBottomSheet` auf Android / zentriertes Dialog auf
  macOS, **Create-Sheet-Konvention**
  (`create_scene_sheet.dart`, `create_block_sheet.dart`) — kein nacktes
  `showDialog`. In-place-Editing (aus #545) bleibt unangetastet; der
  Picker ist eine Auswahl, kein Editor.
- **Display-Name-Abhängigkeit (wichtig):** `CostumeView` hat **kein**
  Namensfeld — die Tile-Identität kommt aus `costumeTileIdentity()`
  (`lib/features/costumes/costume_identity.dart:29-42`, abgeleitet aus
  `details.first.subject`; Naming-Follow-up ist in #543 §3.3 notiert). Der
  Beat-Row muss **denselben Helper** verwenden wie die Tile — **niemals**
  einen Namen aus einem beliebigen Detail erfinden. Bis dahin: Kategorie +
  Icon; `SceneCostumeBeatView.character_name` /
  `costume_category_name` (vom Backend gejoint) verwenden, wo vorhanden.

### 3.3 i18n (§5.3)

- ARB `app_de.arb` (deutsche Vorlage, komplett) + `app_en.arb`
  (Parität — CI-Gate), mindestens:
  `sceneDetailCostumesTitle(count)`, `sceneDetailAssignCostume`,
  `sceneDetailAddChange` („Kostümwechsel"), `sceneDetailRemoveCostumeTooltip`,
  `sceneDetailNoCostumeInScene`, `sceneDetailPickCostumeTitle`,
  `sceneDetailCostumeCueHint` + Error-Copy für die vier Codes oben.
- `flutter gen-l10n` laufen lassen, generierte Dateien committen.
- **Fix in passing (Side-Finding 3 aus #546):**
  `AssignCharacterSheet` (`costumes/widgets/costumes_widgets.dart:363`)
  rendert `Text('Assign character')` hartkodiert — ARB-Key ersetzen
  (verletzt die l10n-Regel und scheitert sonst am Key-Parity-Gate).
- **Side-Finding 1 aus #546:** der Import
  `../costumes/widgets/costumes_widgets.dart` in
  `scene_detail_screen.dart:19` wird durch diese Änderung real benutzt
  (oder löschen, falls am Ende doch ungenutzt).

### 3.4 Design-Dokumentation (§5.4 — Pflicht!)

- `docs/design/screens/scenes.md` **existiert nicht** und wird laut
  `design-doc-workflow/spec.md` Pflicht, weil dieser PR den Screen ändert:
  alle **neun Template-Sektionen** (Purpose & Context, Navigation, Layout,
  Components & Semantics, States, Interactions, Input & Validation,
  Accessibility & i18n, Tests) **plus PlantUML-Salt-Wireframe** des
  Scene-Detail-Screens inkl. Kostüm-Sektion (ein Row, zwei Rows mit `→`,
  Empty State).
- `bash scripts/check-design-diagrams.sh` muss grün sein.
- Byte-Identität `design.md` ↔ `AGENTS.md` (Kontrakt im
  `frontend-flutter/AGENTS.md`) beachten, falls betroffen.

### 3.5 Tests (§8-Flutter-Anteil aus #546)

- **Widget-Tests:** ein Row; zwei Rows mit `→`; `+ Kostümwechsel`;
  Empty-State-Affordance; Picker; **AUTHZ-GATE-Denial-Narrative**
  (Capability-Check blockt vor dem Netzwerkcall); Optimistic + Version-Fence
  (2xx → optimistisches Update, 409 → Refetch).
- **Goldens:** erste Goldens für den Scene-Detail-Screen (existieren
  heute nicht — das ist der First-Golden für diesen Screen).
- Unit: Identitäts-Resolution (Tile-Helper), Order-Rendering (`0 → 1`).
- `coverde`-Threshold auf geändertem Code; `dart format --set-exit-if-changed
  lib test` clean (313-Files-Konvention).

## 4. Explizit NICHT in diesem PR

- **AI-Import-Persistence** (`mapping_kind::SCENE_COSTUME_BEAT`,
  `AssignCharacter`+`AddCostumeBeat`-Dispatch im Apply-Worker,
  per-Figure-Re-Grouping, Version-Ketten-Tests): eigener Umfang, folgt
  separat (Issue §5.8). Der Import regressiert nichts — er persistierte die
  Relation vorher ebenfalls nicht.
- **Kostümverlauf über die Episode** („Kostümverlauf"-View): 0.4.x-Follow-up,
  Daten sind durch das Backend schon ableitbar.
- **Costume-Naming** (#543 §3.3): Row zeigt Kategorie + Icon bis dahin.

## 5. Workflow-Vorgaben

- Version-Bump `0.3.0-alpha.39+49` in `frontend-flutter/pubspec.yaml`.
- **Version-Bump-Tabelle** im PR-Body (Pflicht; `none`-Zeilen explizit für
  `core`/`infra`/`api`, die in diesem PR nicht angerührt werden).
- Conventional Commit (`feat(flutter): ... (issue #546)`), Co-authored-by
  aus `$PI_MODEL`/`$PI_PROVIDER` (SPDX-Header in neuen Dateien, eine Zeile
  pro Autor, append-only).
- PR-Body: Summary/Changes, Version-Bump-Tabelle, Validation-Ergebnisse,
  Acceptance-Checkboxen aus #546 (Flutter-Anteil), Verweis auf PR #578 und
  Issue #14 (US-4.3).
- Nach Merge von PR #578 + diesem PR: `openspec archive
  546-scene-costume-assignment` (dann sind alle Deltas in den Hauptspezs).
- CodeRabbit-Review erwartet: 1:1 threaded replies mit
  `Fixed:`/`Deferred:`/`Not applicable:`-Präfix (Skill
  `coderabbitai-review`).

## 6. Validierung vor dem PR

```bash
cd frontend-flutter
flutter pub get
flutter gen-l10n
dart format --set-exit-if-changed lib test
flutter analyze
flutter test                     # inkl. neuer Widget-Tests + Goldens

cd ..
bash scripts/check-design-diagrams.sh   # aus Repo-Root (design.md-Gate)
```

Backend-Anfassen nur, wenn ein echter Wire-Bug auffällt — dann im PR
dokumentieren und `vendor/breakdown_api` erneut über
`frontend-flutter/scripts/regen-client.sh` regenerieren (byte-stabil).
