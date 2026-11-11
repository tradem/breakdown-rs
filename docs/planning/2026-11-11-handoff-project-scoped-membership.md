<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Übergabe: `fix/live-test-blockers` → `project-scoped-membership`

Stand: 2026-11-11, Branch `fix/live-test-blockers` (9 Commits), `main` unberührt
bei `88960b40`. Arbeitsbaum enthält **11 fremde, unangetastete Änderungen**
(u. a. `backend/CHANGELOG.md`, `crates/infra/src/dev_reset/*`,
`frontend-flutter/lib/features/ai_import/import_jobs/import_target.dart`,
`frontend-flutter/pubspec.yaml` auf `0.4.0-beta.50+142`). **Nichts davon
committen.**

## Auftrag der nächsten Sitzung

`openspec/changes/project-scoped-membership/tasks.md` fertigstellen —
**2.2 bis 3.5**. Erledigt sind 1.1–1.3 (Domain) und 2.1 (Migration).

Reihenfolge:

1. **2.2** `ProjectMembershipProjector` in `crates/infra/src/projectors/` +
   Registrierung in `crates/api/src/main.rs`. Vorlage zuerst lesen:
   `membership.rs` im selben Verzeichnis, `spawn_membership_projector` in
   `projectors/mod.rs`. Version-guarded Upsert (`WHERE version < $N`),
   idempotent, Checkpoint über die bestehende `sierradb_event_checkpoints`-
   Mechanik (kein eigenes DDL). Kategorie des Aggregats: `project_membership`,
   Stream-ID = `project_id`.
2. **2.3** `MembershipRepository::effective_costume_role_in_season`:
   Block-Scope **zuerst** (bestehende `has_active_costume_role_in_season`,
   unverändert), dann Projekt-Scope auf `season.project_id`, sonst deny.
   Fail-closed: Projektions-Miss/Repo-Fehler → `Deny`, nie `Allow`.
   Andockpunkt: `crates/api/src/auth/authorization.rs` (`authorize_season_result`)
   + das Trait in `crates/core`/`crates/infra` — **alle** Impls mitziehen
   (Postgres-Repo **und** Test-Doubles in `crates/test_support`).
3. **2.4** Bootstrap im Season-Command-Adapter: Season-Ersteller →
   `BootstrapProjectOwner` (wird `costume_designer`). Best-effort,
   projektor-unabhängig, idempotent (Hook ist schon im Aggregat).
4. **3.1** `authorize_season_result` über die neue Auflösung verdrahten;
   `// AUTHZ-GATE:`-Kommentarform unverändert lassen.
5. **3.3** Test: `has_active_report_archive_role_in_season` bekommt den
   Projekt-Fallback **nicht** (nur `costume_designer`, `wardrobe_supervisor`).
6. **3.4/3.5** Tier-4-Tests in `crates/integration-tests`: Season **ohne
   Block** + Projektrolle → `POST /v1/ai-import/scripts` mit
   `X-Declared-Season` → `202`, Job mit `block_id = NULL`; Gegentest ohne Rolle
   → `403 ai-import.forbidden`.

## Verifizierte Fakten (bitte nicht neu erraten)

- **kameo_es-Command-Form** (`backend/AGENTS.md` §5 ist jetzt korrekt):
  `pub trait Command<C: CommandName>: Entity { type Error; fn handle(&self, cmd: C, ctx: Context<'_, Self>) -> Result<Vec<Self::Event>, Self::Error>; fn is_state_idempotent(..) -> bool }`.
  Implementiert wird `impl Command<MyCommand> for MyAggregate` — **Command ist
  der Typparameter, das Aggregat das Impl-Ziel.** Quelle:
  `.patches/kameo_es/core/src/lib.rs:32`. Commands brauchen ein
  `impl CommandName { fn command_name() -> &'static str }`. Idempotenz über den
  Hook, **nicht** über ein abgelehntes Command.
- **Warum das Ganze:** `has_active_costume_role_in_season` joint
  `projection_block b ON b.season_id = S` → eine Season ohne Block hat
  strukturell keine Rollen. Deshalb war der block-lose Drehbuch-Import
  (`829` D1) für Kostümdesigner:innen nicht möglich (`403 ai-import.forbidden`).
- **Dev-Datenlage (2026-11-11):** `projection_block` = **0 Zeilen**,
  `projection_season` = 1 (`01a1ca30-2eba-72b1-b530-791eee5b8e4b`, Projekt
  `01a0c8bf-4e2c-7613-8d7f-075eee421b6a`), `projection_membership` = 5
  **Waisen** (Blocks existieren nicht, `dev-user`, Rolle `costume_assistant`).
  Nach 2.2 entweder `reset-dev-data` oder Projektrolle/Bock anlegen, sonst
  bleibt die Projektion inkonsistent.
- **Offene Design-Annahme** (im Proposal markiert, gilt bis Widerspruch):
  Season-Ersteller wird `costume_designer` am Projekt und darf weitere
  Projektrollen vergeben.

## Umgebung / Fallstricke

- **Flutter:** nach einem `unionfs`-Absturz hilft nur
  `fusermount3 -uz ~/.cache/flutter_sdk` (`fusermount` ohne `3` fehlt im PATH).
  Danach `flutter test` / `dart analyze` wieder benutzbar (Flutter 3.47.2).
- **Font-Cache:** liegt in `~/.cache/breakdown/font-index-v1.json` (3,5 MB).
  Override `FONT_INDEX_CACHE_DIR` (Container). Nach Font-Änderungen invalidiert
  er sich pro Datei über `(Pfad, Größe, mtime)`.
- **Backend läuft** auf `:3000` (188 MB, Health grün), gestartet mit
  `./scripts/mem-watch.sh`; Aufzeichnung in `/tmp/api-mem-cache/`.
  Beenden: `systemctl --user stop api-mem-…scope`.
  `scripts/mem-watch.sh --report <dir>` wertet aus.
- **Ausgabe-Filter (`rtk`)** verschluckt Test-/Clippy-/Log-Ausgaben und hat
  schon Fehlannahmen erzeugt: bei verdächtig leerem Output
  `rtk_configure(testOutputAggregation=false, linterAggregation=false,
  buildOutputFiltering=false)`. Die CI-Gates laufen im pre-commit-Hook
  (`bash backend/git-hooks/pre-commit`, `cargo clippy -D warnings` + ast-grep).
- **`read`-Tool** (Source-Filter) entfernt teils trailing comments →
  Edit-`oldText` matcht dann nicht. Bei Mismatch `sed -n … | cat -A` benutzen.
- **Formatieren** pro Datei: `rustfmt --edition 2024 <file>` (nicht
  `cargo fmt` über den Workspace — der würde fremde, schmutzige Dateien
  mitformatieren).
- `#[allow(clippy::unwrap_used)]` braucht einen **same-line** Begründungs-
  Kommentar (ast-grep `allow-panic-lint-justification`).
- Kein `unsafe` in `crates/*` (deshalb kein mmap im Font-Index).

## Definition of Done

- `cargo test -p breakdown_core`, `-p infra`, `-p api` grün;
  `cargo test -p architecture_tests`, `cargo deny check bans`;
  OpenAPI-Drift-Test (kein Contract-Change erwartet, aber der Test muss laufen).
- `openspec validate project-scoped-membership` weiterhin gültig.
- `tasks.md` abgehakt; Commit(s) auf `fix/live-test-blockers`, `main`
  unangetastet, fremde Änderungen nicht gestaged.
- Live-Gegenprobe: Season ohne Block + Projektrolle → Upload `202`; ohne Rolle
  → `403`.

## Kontext zur Vorgeschichte (falls Rückfragen kommen)

Die RAM-Blocker sind erledigt: Typst lud alle System-Fonts eager (7,3 GB RSS,
heaptrack: 9,62 GB Peak) → lazy Faces + Index-Cache (Boot 0,90 s, 188 MB). Die
Terminal-Kills waren `systemd-oomd` auf einer zram-Swap-Schwelle; Drop-in
`backend/scripts/oomd-zram.conf` ist installiert. Der Client zeigte jeden
4xx-Upload als „Netzwerkproblem" (String-Body wurde nicht dekodiert) → gefixt
und getestet.
