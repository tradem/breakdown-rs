<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Arbeitsreihenfolge — House-Keeping der offenen Issues (Stand 2026-11-09)

Lebende Checkliste für die **15 nach dem House-Keeping vom 2026-11-09 noch offenen** Issues,
sortiert nach Abhängigkeiten, Blocker-Wirkung und Datei-Überschneidung. Grundlage ist die
Prüfung jedes offenen Issues gegen Code und gemergte PRs (Belege jeweils in der Zeile).

**Konventionen**

- Größen: **S** ≈ halber Tag, **M** ≈ 1–2 Tage, **L** > 2 Tage.
- Eine Welle ist „fertig", wenn alle ihre Häkchen gesetzt sind; Wellen dürfen sich überlappen,
  wenn die Lanes sich nicht in denselben Dateien treffen.
- Jedes Issue bleibt die Quelle der Wahrheit für Details — hier steht nur Reihenfolge, Größe,
  Abhängigkeit, Blockade und Gate.

---

## Vorab: am 2026-11-09 geschlossen (verifiziert erledigt)

| # | Thema | Belege |
|---|-------|--------|
| **#805** | abgestürzter Apply-Run → `409 ai-import.apply-in-flight` ohne Ausweg | Wire `apply_run_age_seconds`/`stale_after_seconds` (`core/src/error_registry.rs:1187`), `ApplyRunState::owner_silence_at` (`core/src/ai/views.rs:769`), Client-Klassifikation (`data/ai_import_repository.dart:904`), Takeover-UI (`apply_screen.dart:562`), PR #862 + #866 |
| **#827** | Block aus dem Skript lesen und anzeigen | `extract_block_number` (`core/src/ai/preview.rs:594`), `AiImportProgress.block_number` (`ai/views.rs:281`), Chip/Row/Scope-Linie (`job_status_screen.dart:345`, `jobs_screen.dart:321`, `preview_screen.dart:1354`), PR #850 + #851 |
| **#828** | „Block wechseln" / „Block anlegen" im Importziel | `import_submit_screen.dart:604-729`, ARB de+en, Widget-Test, PR #853 + #860 |

---

## Welle 1 — Aufräumen (kein Risiko, zuerst)

- [ ] **#839** — gemergte Golden-`failures/`-Artefakte untracken · **S** · Tooling
      → [Issue](https://github.com/tradem/breakdown-rs/issues/839)
      *`frontend-flutter/.gitignore:62` deckt `**/failures/` bereits ab; offen ist nur
      `git rm -r --cached` auf **32** Binärdateien. Macht jedes spätere Golden-Rebaseline
      (u. a. #840) diff-sauber — deshalb vor #840.*
- [ ] **#814** — SPDX-Header: `--check`-Modus + CI-Gate, dann Retrofit · **S** (Gate) + **L**
      (mechanisch) · Tooling
      → [Issue](https://github.com/tradem/breakdown-rs/issues/814)
      *Der Zähler **wächst** (Issue nennt 346, heute **373** Dateien ohne Header) — je früher,
      desto billiger. Zwei getrennte PRs: (a) `--check`-Modus in
      `scripts/add-spdx-headers.sh` (hat heute nur `Usage: [directory]`) + CI-Job;
      (b) ein einziger mechanischer Retrofit-Commit. (b) nur in einem ruhigen Fenster, wenn
      kein langlebiger Branch offen ist — 373 Dateien sind eine Konflikt-Maschine.*
- [ ] **#838** — `component.appBar`-Token-Gruppe · **S–M** · Flutter + OpenSpec
      → [Issue](https://github.com/tradem/breakdown-rs/issues/838)
      *`lib/design/header_metrics.dart:23` sagt explizit „deliberately NOT introduced",
      `design/tokens/` hat nur `color/elevation/size/typography`. Braucht ein Mini-OpenSpec-Change,
      weil es das Non-Goal „keine Component-Tokens" lockert.*

## Welle 2 — Reibung entfernen

- [ ] **#820** — `audit_cross_cutting` 6.1 flake (Tokio-Runtime-Shutdown) · **M** · Backend-Test
      → [Issue](https://github.com/tradem/breakdown-rs/issues/820)
      *Kostet bei jedem PR CI-Zeit und Vertrauen. Race ist lokalisiert: eine Container-Paar-Instanz
      in `SharedContainers`/`CONTAINERS: OnceLock` (`integration-tests/tests/audit_cross_cutting_tests.rs:107-143`),
      initialisiert in einer Runtime, die der Harness beim Testende herunterfährt. Je weniger
      Feature-Branches parallel laufen, desto besser messbar — deshalb hier und nicht später.*
- [ ] **#840** — restliche Season-Label-Stellen konvergieren, „Season/Staffel" vereinheitlichen ·
      **M**, mechanisch · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/840)
      *`seasonDisplayLabel` existiert, wird aber nur in der Definition und in
      `shell/season_scope_chip.dart` benutzt; **11** Inline-`seasonsDefaultTitle`-Stellen bleiben
      (`seasons_screen.dart:279,305`, `shell/location_strip.dart:22`,
      `shell/production_overview_screen.dart:58`, `fundus/fundus_screen.dart:255,286`,
      `pieces/piece_detail_screen.dart:246,335`). Dazu Glossar-Entscheid, de/en-Parität und
      Golden-Rebaseline → profitiert direkt von #839.*

## Welle 3 — Den AI-Import-Rand schließen

- [ ] **#817** — toten persistierten Season-Anker evicten · **M** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/817)
      *`shell/active_season_store.dart` löst eine unbekannte id bewusst auf `null` auf, evictet
      aber nie; das Muster für die Reparatur liegt schon vor
      (`auth/active_block_store.dart:165` `removeScopeIfMatch`, genutzt in
      `blocks/active_block_gate.dart:154`). Repariert die Hälfte, die #809 nur tolerant gemacht
      hat → rundet den Dev-Reset-Pfad ab.*
- [ ] **#816** — `GET /v1/me/capabilities` für ein exaktes Pre-Tap-Gate · **M–L** · Backend + Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/816)
      *Achtung Zusatzaufwand: es gibt heute **keinen** `/v1/me/*`-Namespace in
      `backend/openapi.yaml` (nur `/v1/meta/*`) — die Route ist also auch eine
      Namespace-Entscheidung. Umfang: utoipa-Handler + `openapi.yaml` + `scripts/regen-client.sh`
      (Drift-Gate, keine Hand-Edits unter `vendor/breakdown_api/`) + Settings-Eintrag
      (AUTHZ-GATE-Spiegel exakt) + Widget-Tests + `AGENTS.md` §1 + `docs/design/screens/settings.md`
      + `flutter-client-authz`-Requirement. Nach #817, weil beide aus der #809-Familie kommen und
      sich den Settings-Screen teilen.*
- [ ] **#871** — Provider-Circuit-Breaker, Chunk-Resume, Retry-Policy · **L** (3 PRs) · Backend
      → [Issue](https://github.com/tradem/breakdown-rs/issues/871)
      *Größter offener Posten mit echtem Geld-Impact: `infra/src/ai/workers.rs` hat heute weder
      einen Breaker noch Chunk-Resume (`grep` auf `circuit_breaker` / `resume_from` /
      `first_incomplete` = leer). Drei separable Arbeitsströme (A fail-fast, B Resume, C
      Retry-Policy) — je ein PR, ein Design. Kein Hardware- oder Entscheidungsblocker, deshalb
      darf es als einziges Issue der Welle beliebig lange dauern.*

## Welle 4 — bewusst zuletzt (blockiert oder Epic)

- [ ] **#363** — macOS-Runner + OIDC-Redirect-Scheme · **M** (Scaffold) + **blockiert** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/363)
      *Kein `frontend-flutter/macos/` vorhanden, kein `macos`-Job in `.github/workflows/`. Scaffold
      ist möglich, Build/Verify braucht Apple-Hardware bzw. einen macOS-Runner — deshalb erst,
      wenn dieser zur Verfügung steht. Nicht mit #417 verwechseln (andere Baustelle).*
- [ ] **#417** — Instance-Onboarding für offizielle Android-Clients · **blockiert** · Produkt
      → [Issue](https://github.com/tradem/breakdown-rs/issues/417)
      *Explizit gesperrt: „Do not start implementation before `add-android-release-workflow` has
      cut its first real release"; zusätzlich muss ADR-032 (TLS-Pinning/TOFU) per OpenSpec neu
      verhandelt werden. Kein Code, solange beide Gates nicht erfüllt sind.*
- [ ] **#674 → #673 → #676** — Figuren-Bilder + AI-Vorschlagbilder (Diffusion) · **L**, design-lastig
      → [#674](https://github.com/tradem/breakdown-rs/issues/674) ·
      [#673](https://github.com/tradem/breakdown-rs/issues/673) ·
      [#676](https://github.com/tradem/breakdown-rs/issues/676)
      *Prozesskette: #674 ist die `openspec explore`-Sitzung (7 offene Designfragen), ohne die #673
      nicht implementiert werden darf; #676 ist reine UX auf der #673-Pipeline. Der Seam ist
      vorbereitet (`AiConfig.image_model` ist bis heute brach, `LlmProvider` ist
      `#[non_exhaustive]`), aber es existiert kein `FigureImage`/`DiffusionProvider`-Typ.*
- [ ] **#16 → #17** — Budget/Kalkulation (US-5.1 → US-5.2) · **L–XL**, OpenSpec-Vorlauf · Backend + Flutter
      → [#16](https://github.com/tradem/breakdown-rs/issues/16) ·
      [#17](https://github.com/tradem/breakdown-rs/issues/17)
      *Kein `CostCalculation`/`CalculationItem` im Backend — neuer Aggregate-Strich, also erst
      Proposal (Aggregate-Grenze, Währungs-/Rundungsregeln, Bezug zu Outfit/Piece), dann Bau.
      Unabhängig vom Rest, kann jederzeit als eigene Spur starten.*

---

## Kritischer Pfad

```
#839 ──→ #840            (Golden-Rebaseline nur einmal anfassen)
#814 (Gate-PR) ──→ #814 (Retrofit-Commit, Fenster ohne Feature-Branches)
#838                     (eigenes Mini-OpenSpec-Change)
#820                     (CI-Rauschen)
#809-Familie: #817 ──→ #816
#871                     (frei, größter Geld-Impact)
blockiert: #363 → Apple-Hardware · #417 → erster Release + ADR-032
Epics:  #674 → #673 → #676        #16 → #17
```

## Regeln für diese Reihenfolge

1. **#839 vor #840** — erst die gemergten Golden-Artefakte untracken, dann Labels/Goldens
   ändern; sonst enthält die #840-Re-Baseline wieder 32 Binärdateien, die niemand reviewen kann.
2. **#814-Retrofit nie parallel zu #871** — der Retrofit tauscht Header in 373 Dateien, #871
   arbeitet an `infra/src/ai/workers.rs` und `queue.rs`.
3. **#839/#814-Retrofit in einem ruhigen Fenster** — beides sind Baum-weite Commits; mitten in
   einer Feature-Serie erzeugen sie Rebase-Schmerz ohne Gewinn.
4. **#816 erst nach #817** — beide fassen Settings/Session-Scope an; #817 ist der kleinere,
   risikoärmere Teil derselben #809-Familie.
5. **#871 als einziges Issue ohne Deadline behandeln** — drei PRs, ein Design, ein Review-Pfad;
   es blockiert niemanden, also nicht in den kritischen Pfad ziehen.
6. **Epics starten mit dem Prozess-Issue, nicht mit Code** — #674 (`openspec explore`) und ein
   Proposal für #16/#17 können jederzeit neben Welle 1–3 laufen; Implementierung erst danach.
7. **#363/#417 nicht einplanen, solange ihr Gate fehlt** — ein „angefangenes" macOS-Scaffold oder
   eine Instance-Auswahl vor dem ersten Release ist Arbeit ohne Abnehmer.
8. Nach jedem Issue, das Goldens anfasst: `flutter test --update-goldens` nur für die betroffenen
   Dateien, damit die Re-Baseline im PR nachvollziehbar bleibt.
