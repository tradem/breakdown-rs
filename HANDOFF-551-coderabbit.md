<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Übergabeprompt — PR #551, CodeRabbit-Feedback finalisieren

Starte in `/home/digiwitcher/Projekte/repos/breakdown-rs`.

## 0. Vertrauensregel (wichtigste Anweisung)

Die vorherige Sitzung ist als **vergiftet** markiert. Dieser Prompt beschreibt
geprüfte Fakten, aber **prüfe vor jeder Änderung selbst nach** (`git status`,
`git diff`, `gh api`). Behaupte nichts über den Repo-Zustand, was du nicht in
dieser Sitzung gesehen hast. Wenn eine Aussage hier und die Realität
divergieren: **Realität gewinnt**, und sag dem User, was abweicht.

## 1. Kontext

- Branch: `fix/ai-import-and-photo-pipeline`
- PR: **https://github.com/tradem/breakdown-rs/pull/551** (`tradem/breakdown-rs`)
- Stand: PR ist offen, alle 31 CI-Checks waren grün, **Mergeable/BLOCKED**
  (Branch Protection braucht menschliche Approval — kein Agent-Job).
- Commit-Stand (`git log --oneline -10`): letzte Commits `a4caa18e`, `7085c19a`,
  `833b8c9e`, `ca7ca14c`, `b5645af0`, `7dfb54de`, `a53ee332`, `511baaa9`, ...
- **Working Tree ist NICHT committet.** 13 modifizierte Dateien = die
  CodeRabbit-Fixes (Verifizierung siehe §2):
  `backend/crates/{api/src/handlers/mod.rs, core/src/ai/{preview.rs,preview_tests.rs},
  infra/src/ai/{tests.rs,workers.rs}, infra/src/photo/sagas/thumbnail.rs,
  infra/src/vault.rs, integration-tests/tests/photo_round_trip.rs}`,
  `docs/design/glossary.md`,
  `frontend-flutter/lib/data/ai_import_repository.dart`,
  `frontend-flutter/lib/features/costumes/costume_detail_screen.dart`,
  `frontend-flutter/test/features/costumes/costume_detail_screen_test.dart`,
  `openspec/changes/ai-import-character-costumes/tasks.md`
- Untracked und **nicht** dazugehörig (nicht committen!): `.cache/`,
  `HANDOFF-551-coderabbit.md` (dieses Übergabedokument — Arbeitsnotiz),
  `frontend-flutter/.mcp.json`, `frontend-flutter/.pi/**`,
  `frontend-flutter/assets/certs/dev/ca.pem.orig-placeholder`,
  `openspec/changes/453-costume-season-repertoire/`

## 2. Die 12 CodeRabbit-Kommentare — Status

 hole sie neu und mappe **nach Datei/Zeile**, nicht nach IDs aus diesem Prompt:
```bash
gh api repos/tradem/breakdown-rs/pulls/551/comments --paginate \
  --jq '.[] | "\(.id) \(.path):\(.line // .original_line) \(.body | split("\n")[0] | .[0:90])"'
```

Als diese Sitzung endete, geprüft in §-Notation ([x] = Fix im Working Tree):

- [1] Body-Limit der Foto-Upload-Route: war `.route_layer` (griff auf ALLE
  Routes), jetzt MethodRouter-`.layer` nur auf der Upload-Route
  (`handlers/mod.rs:~5917`, `photo_body_limit` bei `:5667`) — **im Tree**
- [2] Deutsche Überschriften-Präfixe: space-terminierte Formen (`"INNEN "`,
  `"AUSSEN "`) erfordern jetzt Großschreibung des Orts via
  `space_form_is_heading()` (`core/src/ai/preview.rs:759`, genutzt `:780`);
  3 neue Tests in `preview_tests.rs` — **im Tree**
- [3] Vault-Besitz: **DEFERIERT**, GitHub-Issue **https://github.com/tradem/breakdown-rs/issues/552**
  ist angelegt (security-Label, enthält Evidenz + Required-Work). Grund:
  `projection_settings` hat keine Owner-Spalte
  (`backend/crates/infra/migrations/20260801000001_settings_credentials.up.sql`) —
  ohne Migration keine Besitzprüfung an der API-Kante. Reply-Status: `Deferred:`
  mit Link auf #552.
- [4] `scene_index` Off-by-one: jetzt `context.scenes.len()` (0-basiert) statt
  `scene_ordinal` (1-basiert global); Assertion
  `assert_eq!(uncertainty.scene_index, 0)` in `infra/src/ai/tests.rs:2855` — **im Tree**
- [5] Notes-Schritt nutzt `recover_version(notes)` (`workers.rs:1376`);
  **Regressionstest vorhanden und rückwärts-verifiziert**:
  `script_apply_recovers_when_only_the_notes_confirm_crashed` — mit Fix `ok`,
  Fix provisorisch entfernt → `FAILED` (beweist Testwert). Insert-Reihenfolge
  für 1 Szene + 1 Figur + 1 Kostüm: #1 Szene, #2 Figur, #3 Costume-Create,
  **#4 Notes-Confirm**, #5 Bind — `fail_nth_insert(4)` trifft genau das Fenster.
- [6] Thumbnail-Saga-Terminal-Guard `derived_failed`
  (`infra/src/photo/sagas/thumbnail.rs:216`, `if derived_failed` bei `:224`) —
  **im Tree, aber OHNE eigenen Test.** `photo_saga_redelivery` läuft grün
  (gilt auch für den Guard), deckt aber den Both-`Failed`-Fall nicht positiv ab.
  Offene Option (nicht angefangen): Prädikat als freie Fn
  `derived_variants_failed(&PhotoAggregate) -> bool` neben `variant_ready`
  (`:515`) extrahieren und im bestehenden `mod tests` (`:552`) unit-testen —
  billig, braucht keine Container.
- [7] `settings_id_from_binding_key` (`infra/src/vault.rs:685`): Rotations-Suffix
  wird als UUID geparst, `settings-<uuid>-garbage` → `None` (fail-closed) — **im Tree**
- [8] Whitespace-Artefakte in `photo_round_trip.rs`-Fehlermeldungen behoben.
  **Fallstrick:** Rust hat **keine** benachbarte String-Konkatenation — Fix nutzt
  echte `\`-Fortsetzungen. War zwischenzeitlich kaputt (clippy-Fehler),
  nach dem zweiten Fix ok — **im Tree**
- [9] `docs/design/glossary.md`: `aiPreviewCostume.heading` → `aiPreviewCostumeHeading`
  (flach, konsistent zur Inventar-Konvention; die beiden Namespaces sind
  bewusst getrennt) — **im Tree**
- [10] `ai_import_repository.dart`: Typo `Djos` → `Dio's` — **im Tree**
- [11] Kostüm-Detail-Reload nach Upload/Delete (`_loadDetail()`, 4 Vorkommen in
  `costume_detail_screen.dart`) + 2 Widget-Tests mit `detailQueue` im Fake
  (`costume_detail_screen_test.dart:256`) — **im Tree**
- [12] Design-D-Referenzen umnumeriert (7 Stellen: tasks.md, `workers.rs`,
  `preview.rs`) — **im Tree**

## 3. Was zu tun ist (Reihenfolge)

1. **Verifizieren** (nichts davon ist nach den letzten Edits gelaufen, außer wie
   angegeben):
   ```bash
   cd backend && cargo fmt --all && cargo fmt --check --all
   cargo clippy --all-targets --all-features -- -D warnings   # war grün VOR [5]-Test-Edit
   cargo test -p breakdown_core -p infra -p api               # 70 ok-Blöcke VOR [5]-Test
   cargo test -p integration-tests --test photo_round_trip --test photo_saga_redelivery \
     --test ai_import_mapping_reservation --test ai_mapping_mutation_hardening  # alle grün
   ```
   Die Container-Tests brauchen die Dev-Runtime (`backend/docker-compose.dev.yml`).
   `cargo` und `flutter` laufen parallel gefahrlos (verschiedene Locks).
2. **Flutter-Verifikation** (nach [9]/[10]/[11] nicht mehr gelaufen):
   ```bash
   cd frontend-flutter && flutter analyze && dart format --set-exit-if-changed . && flutter test
   ```
   Vorher-Stand: 1082/1082 Tests grün. Glossary-Checker:
   `bash scripts/check_glossary_identifiers.dart` (601 Identifier, 620 Keys de/en-Parität).
3. **Optional, aber erwähnenswert:** [6]-Unit-Test (§2 Punkt [6]). Wenn du ihn
   nicht schreibst, im Reply nicht behaupten, er existiere.
4. **Commit** aller 13 Dateien als EIN Commit, Message sagt klar, was verifiziert
   und was defert ist (mit Link #552). Header-Konvention:
   ```
   // SPDX-License-Identifier: AGPL-3.0
   // Copyright (C) 2024-2026 Breakdown RS Contributors
   // Co-authored-by: <modell> (<provider>)
   ```
   Co-Autor dieser Sitzung war `qwen3.8-flash (opencode-go)`. Pre-Commit-Hooks
   laufen automatisch (gitleaks → fmt → clippy `-D warnings` → check →
   ast-grep Guardrails). **`ast-grep`-Guardrail:** `mappings.find(...)` im Worker
   braucht `// ast-grep-ignore: cqrs-boundary` (CQRS-Boundary-Regel).
5. **Push** auf den PR-Branch.
6. **12 Thread-Replies** — Pflichtvorgabe aus dem Skill
   `.pi/skills/flutter-coderabbitai-review/SKILL.md`: ein Reply **pro Thread**
   (kein Sammelkommentar), Status-Vokabular als **erstes Token**:
   `Fixed:` / `Deferred:` / `Not applicable:`. Reply via
   `gh api repos/tradem/breakdown-rs/pulls/551/comments -F in_reply_to=<id> -f body=...`.
   Jedes `Fixed:` muss Datei+Zeile nennen und warum der Fix das Problem löst.
   [3] → `Deferred:` mit Begründung (Schema) + Link auf Issue #552.
7. **Thread-Abdeckung prüfen:** verifiziere, dass kein Thread unbeantwortet ist
   (Skill: die Aggregat-Prüfung muss leer/`UNREPLIED_OR_DUPLICATE`-frei sein).
8. **Re-Review-Request** als PR-Kommentar posten.
9. Nichts weiter annehmen: Merge braucht menschliche Approval.

## 4. Offene, bewusst NICHT-hier-Arbeits (nicht anfangen ohne User-Freigabe)

- **tasks.md 6.2 und 8.3–8.5 (Live-Import):** User entschied explizit
  „Erst 8.1/8.2 beenden, Live aus". Erfordert API-Start (Migration
  `20260927000001_ai_import_mapping_key` ist **nirgends gelaufen**) und einen
  **bezahlten** Provider-Lauf. Nur mit ausdrücklicher Approval.
- **Issue #552** (Vault-Besitz): eigene Änderung, braucht Migration +
  API-Kanten-Check + Problem-Code (ADR-031).
- Bekannte Lücke: im Decode-Fehler-Pfad bleibt `Original` auf `Pending`
  (in `photo_round_trip` bewusst aus der Terminal-Prüfung raus, als 9.6 notiert).

## 5. Werkzeug-Fallstricke aus der letzten Sitzung

- RTK-Source-Filtering hat Edit-Anker verstümmelt → bei wiederholten
  „old text must match"-Fehlern `rtk_configure` `sourceCodeFilteringEnabled:false`,
  Datei re-readen, Fix, wieder an.
- `rg` mit Klammern im Pattern braucht `-F` (regex-Parse-Fehler).
- Testnamen können irreführende grep-Treffer liefern
  (`join_panicked_worker_does_not_panic` ≠ Fehler). Auf
  `test result: FAILED` / `FAILED\.` prüfen, nicht auf Wortteile.
- Rust: keine benachbarten String-Literale (kein C-artiges Aneinanderreihen).
- `generated` Dart-Client unter `frontend-flutter/vendor/breakdown_api/` ist
  rebuild-only — niemals von Hand editieren, sondern `bash scripts/regen-client.sh`.
