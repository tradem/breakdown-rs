<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Arbeitsreihenfolge — Issues vom 2026-11-04

Lebende Checkliste für die am **2026-11-04** angelegten Issues (#821–#834), sortiert nach
Abhängigkeiten, Blocker-Wirkung und Datei-Überschneidung. Grundlage ist die Analyse-Session zu
KI-Import, Shell/Header, Blöcken und Szenen-Screen.

**Konventionen**

- Größen: **S** ≈ halber Tag, **M** ≈ 1–2 Tage, **L** > 2 Tage.
- Eine Welle ist „fertig", wenn alle ihre Häkchen gesetzt sind; Wellen dürfen sich überlappen,
  wenn die Lanes (Backend ↔ Frontend) sich nicht in denselben Dateien treffen.
- Jedes Issue bleibt die Quelle der Wahrheit für Details — hier steht nur Reihenfolge, Größe,
  Abhängigkeit und Gate.

---

## Welle 0 — Entsperren (zuerst)

- [ ] **#821** — Apply scheitert mit `422 domain.validation` bei wiederholten
      `(scene_index, field)`-Blockern · **S** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/821)
      *Harter Blocker: ohne diesen Fix ist jede Preview mit doppelten Blocker-Paaren nicht
      anwendbar. Reine Client-Dedup, kein Backend.*
- [ ] **#826** — Prompt-Regeln: `(OT)` = Komparse/extra, `Ep.: <n>/<suffix>` = Episode `<n>` · **S**
      · Backend
      → [Issue](https://github.com/tradem/breakdown-rs/issues/826)
      *Schneidet den Rauschpegel (28 Blocker → 8 Fragen → nahe 0), der #821 überhaupt auslöst.
      Parallel zu #821 mergen (andere Dateien).*
- [ ] **Rollout-Gate zu #826:** gespeicherten Skript-Prompt im AI-Config zurücksetzen/aktualisieren
      (`GET /v1/ai-import/defaults` + Reset-Affordance). Ohne diesen Schritt bleibt die Verbesserung
      in einer bestehenden Installation unsichtbar.

## Welle 1 — Kleine, sichtbare Fehler (drei parallele Lanes)

**Lane A — AI-Import-UI**

- [ ] **#831** — verwendet vs. konfiguriertes Modell, „Episode wählen…" entfernen, „Zum Import
      senden" erst mit Datei · **S** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/831)

**Lane B — Shell/Typografie (Goldens nur einmal anfassen)**

- [ ] **#825** — Season-Pille: Nummer immer, Name nach dem Trenner; leere Titel · **S** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/825)
- [ ] **#824** — Header zu hoch: Statusbar doppelt gerechnet + un-tokenisierte AppBar · **M** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/824)
- [ ] *(optional, gleiche Testfamilie)* **#817** — persistierten Season-Anker verwerfen, wenn er auf
      keine Zeile zeigt · **S**

**Lane C — Blöcke (gleiche Dateien, deshalb direkt hintereinander)**

- [ ] **#832** — AppBar-Pille druckt Capability-Codes; Blöcke ohne Zeitraum zeigen „– – –" · **S** ·
      Flutter → [Issue](https://github.com/tradem/breakdown-rs/issues/832)
- [ ] **#833** — Start/Ende über Date-Picker statt `YYYY-MM-DD`-Text · **S** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/833)
      *Setzt die Ordnungsprüfung `start ≤ end` clientseitig um, die #832 als Backend-Lücke notiert.*

## Welle 2 — Shell-Aufräumen

- [ ] **#823** — Plus-Action nur auf dem Script-Ziel + KI-Import-Aufträge (dort nur „Import") · **S–M**
      · Flutter → [Issue](https://github.com/tradem/breakdown-rs/issues/823)
      *Nach #824/#825: dieselben Dateien (`app_shell.dart`, `kShellFabBottomClearance`,
      `app_shell_test.dart`) und Goldens.*

## Welle 3 — AI-Import: Block & Ziel

- [ ] **#827** — Block aus dem Skript lesen und anzeigen (Progress + Preview), Zielblock benennen ·
      **M** (2 PRs: Backend-Scan → Flutter) · → [Issue](https://github.com/tradem/breakdown-rs/issues/827)
- [ ] **#828** — „Block wechseln" / „Block anlegen" im Importziel · **S** · Flutter
      → [Issue](https://github.com/tradem/breakdown-rs/issues/828)
      *Kann parallel zu #827 starten; nur der „aus Skript übernehmen"-Teil wartet auf #827.*
- [ ] **#829 (nur Design)** — Importziel aus dem Skript: block-loser Upload + spätes Anhängen;
      **Autorisierungsentscheidung + OpenSpec-Change schreiben** · → [Issue](https://github.com/tradem/breakdown-rs/issues/829)
- [ ] **GATE:** keine #829-Implementierung, bevor diese Entscheidung dokumentiert ist (Season- vs.
      Block-Scope der Upload-Autorisierung, Attach-Contract, Cross-Block-Guard im Apply).

## Welle 4 — Apply-Robustheit (offene Altlast, gehört hierher)

- [ ] **#805** — abgestürzter Apply-Run lässt den Client auf `409 ai-import.apply-in-flight` warten ·
      **M** → [Issue](https://github.com/tradem/breakdown-rs/issues/805)
      *Erst sinnvoll, wenn Apply wieder benutzbar ist (#821/#826). Nicht parallel zur
      #829-Implementierung — beide betreffen Run-/Guard-Pfad.*

## Welle 5 — Provider-Transparenz

- [ ] **#822** — degradierter LLM-Provider (wiederholte 503s) als aggregierter Zustand · **M**
      → [Issue](https://github.com/tradem/breakdown-rs/issues/822)
      *Backend-Entscheidung nötig: eigener Problem-Code für den Provider-Pfad vs. `dependency`-Feld
      am Attempt; dazu Client-Aggregation + Terminal-Copy-Fix (dead_letter).*

## Welle 6 — Szenen-Redesign (#834, PR für PR)

- [ ] **#834 PR 1** — visuelle Hülle: Titel „Szene {n}", Kopfblock im Inhalt, `SectionCard` ohne
      Divider, **default nichts expanded**, Meta-Chips inkl. „AI-generiert"-Badge · **M** · Flutter
- [ ] **#834 PR 2** — Synopsis als eigene Sektion (Volltext, Badge, Leerzustand) · **S** · Flutter
- [ ] **#834 PR 3** — Backend: Decision-Model-Scores beim Apply persistieren (Event additiv,
      Projektionsspalten, `SceneView`, OpenAPI + Dart-Client-Regen) · **M** · Backend
- [ ] **#834 PR 4** — Sterne in der Synopsis-Sektion (`AiScoreStars`, ehrliche Abwesenheit) · **S** ·
      Flutter
- [ ] **#834 PR 5** — Szenen-Editor: alle Felder (Nummer, Ort, Stimmung, Script-Tag, Synopsis),
      `version`-Echo, optimistischer Overlay + code-basierte Fehlernarrative · **M** · Flutter
- [ ] **Frühstart-Option:** PR 1 (+2) darf ab Welle 1 parallel laufen — eigene Datei, keine
      Überschneidung — aber **nach #824**, das die Header-Baseline definiert.

---

## Kritischer Pfad

```
#821 ─┐
      ├─→ #805 ─→ (#829 Entscheidung → #829 Implementierung)
#826 ─┘
#825 → #824 → #823
#832 → #833
#827 → #828
#822
#834 PR1(+2 parallel) → PR3 → PR4 → PR5
```

## Regeln für diese Reihenfolge

1. **#821 vor allem anderen mergen** — es ist der einzige echte Blocker im Produktfluss.
2. **#826 nur mit Rollout-Schritt** (gespeicherter Prompt), sonst wirkungslos.
3. **#829 nicht implementieren, bevor die Autorisierungsfrage entschieden ist** — sonst importiert
   die UI sichtbar in Block 2, während der Job auf Block 1 festhängt.
4. **#834 nie als ein PR** — PR 1 allein erfüllt die PO-Anforderung (kein Expanded, keine Linien,
   „Szene 12") und ist unabhängig reviewbar.
5. **Nicht in die Reihenfolge einplanen:** #830 (Token-Rotation) ist Betrieb — sofort erledigen.
6. Nach jedem Issue, das Goldens anfasst: `flutter test --update-goldens` nur für die betroffenen
   Dateien, damit die Re-Baseline im PR nachvollziehbar bleibt.
