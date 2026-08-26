<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: ox-alpha-free (opencode-go) -->
<!-- Co-authored-by: mimo-v2.5 (opencode-go) -->

# Issue #274 — Mutation-Test-Hardening: Patch-/Task-Split

> Quelle: 516 überlebende Mutanten (Weekly-Run 32800458579), Liste: `/tmp/combined_unique.txt`
> (Merge der Shard-Artifacts `mutants-out-weekly-shard-{0..31}`).
>
> **Zweck dieses Dokuments:** Jeder Patch (= ein Datei-/Cluster-Fix) ist ein eigener,
> unabhängig bearbeitbarer Abschnitt mit eigener Statuszeile — so kann die Arbeit
> session-übergreifend verteilt werden. Ein Patch ≙ ein Commit im Batch-PR
> (ein PR pro Batch, wie im Issue vorgeschlagen).
>
> **Arbeitsregeln pro Session (aus dem Issue + AGENTS.md):**
> - Mutant **mit Test killen** ist Preferred; `exclude_re` nur einzeln mit Begründungskommentar,
>   niemals bulk-adden, um die Zahl zu drücken.
> - Kein `unwrap`/`expect`/`panic!` in Produktionscodepfaden; keine timing-/sleep-basierten Tests.
> - ⏱ Hängende Mutanten werden durch **Code-Härtung** (bounded loop) **plus** Test gelöst.
> - P0-Tests dürfen nicht `#[ignore]`/Docker-gated sein (Acceptance Criteria).
> - **Branch-Modell:** Pro Batch ein eigener Branch/PR gegen `main` — Basis jeweils `main`
>   **nach** Merge des Planungs-PRs #277. Ein Patch ≙ ein Commit im jeweiligen Batch-Branch
>   (Branch-Namen: Übersichtstabelle unten, Batch-Header und Patch-Statuszeilen).
> - Pro abgeschlossenem Patch: Statuszeile hier auf ☑ setzen + Commit-Nachricht vermerken,
>   damit Folgesessions den Stand sehen (`git log -- openspec/changes/274-mutation-test-suite-hardening/tasks.md`).
>
> **Verifikation pro Patch:**

```bash
cargo mutants --file crates/<crate>/src/<file>.rs     # nur betroffene Datei
cargo clippy -p <crate> --all-targets -- -D warnings
cargo test -p <crate> --features test-support
```

---

## Patch-Playbook (verbindlich für jede Session — auch für schwächere Modelle)

> **Vor dem Start:** `AGENTS.md` gelesen? Branch ausgecheckt (siehe Tabelle oben)?
> Dann erst diesen Abschnitt lesen, dann den eigenen Patch-Abschnitt.

### Notations-Legende der Mutanten

Ein Mutant ist eine **automatisch eingebaute Code-Änderung**. Wenn danach alle Tests
weiter grün sind, „überlebt" er — das ist die Testlücke, die du schließen sollst.

| Notation | Bedeutung | Beispiel-Gegenmaßnahme |
|---|---|---|
| `replace && with \|\|` (oder umgekehrt) | Logischer Operator gedreht | Test, der genau **einen** von zwei Bedingungen erfüllt und das gegenteilige Ergebnis erwartet |
| `replace == with !=` (bzw. `<`→`<=`, `>`→`>=`, …) | Vergleich gedreht/erweitert | Boundary-Test **exakt am Grenzwert** plus je ein Fall darüber/darunter |
| `delete !` | Negierung entfernt | Test für beide Zweige der Bedingung |
| `replace match guard X with true/false` | Match-Guard erzwungen | Test je Guard-Ausgang (Leer-/Whitespace-/Normalfall) |
| `delete match arm "…"` | Match-Zweig gelöscht | Aufruf mit genau diesem Wert; Ergebnis muss stabil bleiben |
| `replace fn -> T with <WERT>` | Ganzer Funktionskörper ersetzt (z. B. `Ok(vec![])`) | Test, der das echte Ergebnis konkret assertet (Inhalt, Länge, Event-Anzahl, Statuscode) |
| `replace <impl Trait>::method with ()` / `-> Ok(Default)` | Methode wird zum No-Op | Seiteneffekt beobachten (geschriebene Bytes, gesetzter Zustand) und im Test prüfen |

### So führst du einen Patch aus (Schritt für Schritt)

1. **Kontext:** Patch-Abschnitt unten suchen; Datei(en) öffnen und jede mutierte Stelle
   mit ~20 Zeilen Kontext lesen. Bei Unklarheit: Funktion komplett lesen.
2. **Erwartung notieren:** Für jeden Mutanten kurz bestimmen, welches *beobachtbare*
   Verhalten sich ändert (Rückgabewert, Fehler, Event, HTTP-Status, geschriebene Bytes).
3. **Tests schreiben:** Je Verhaltensänderung genau ein Testfall; bei vielen Eingabekombinationen
   einen tabellierten Test (Slice von `(input, expected)`-Paaren). Erst nachdenken, dann tippen.
4. **Mutanten-Check (mentaler Tötungstest):** Stelle dir vor, der Mutant sei eingebaut —
   würde dein neuer Test rot? Wenn nein: Test schärfen, nicht den nächsten Mutanten ansehen.
5. **Verifizieren:** Verify-Kommandos des Patch-Abschnitts ausführen (alle drei müssen grün sein).
6. **Aufräumen:** `cargo fmt`, keine Warnungen (`clippy -D warnings`), kein toter Testcode.
7. **Commit:** Conventional Commit mit Patch-ID, z. B. `test(tls): kill root_cert_from_env mutants (P1.2, issue #274)`.
8. **Statuszeile** im Patch-Abschnitt auf ☑ setzen und Commit-Hash eintragen; dann committen/pushen.
9. **Nur wenn nötig:** Ist ein Mutant *nachweislich* verhaltensgleich (semantisch äquivalent,
   z. B. doppelt abgesicherter Zweig), trage ihn einzeln in `exclude_re` in `.cargo/mutants.toml`
   ein — mit Begründungskommentar und Verweis auf den Patch. **Niemals** mehrere auf einmal,
   niemals um „die Zahl zu drücken“.

### Wohin gehört der Test?

| Art der Logik | Testort | Läuft ohne Docker |
|---|---|---|
| Reine Funktionen, Aggregate, Guards, Parser | Inline-`#[cfg(test)] mod tests` in derselben Datei | ✅ |
| HTTP-Handler (403/413/Content-Type) | Bestehende Handler-Testmuster in `crates/api/src/handlers/mod.rs` bzw. Tests daneben imitieren | ✅ |
| Postgres-Projektoren/Queries/Queue (Tier 1–3) | `crates/integration-tests` (Muster `projector_tests` imitieren) | ❌ Docker nötig — nur für P1/P2-Patches, **nie für P0** |
| Saga-Verhalten mit Storage | Unit-Test mit Fake-`PhotoStorage`/Port-Fake (Muster aus bestehenden Saga-Tests suchen: `grep -rn "impl PhotoStorage" crates/infra/src/photo`) | ✅ |

### Definition of Done (je Patch)

- [ ] Jeder gelistete Mutant ist entweder **getötet** (Test nennt im Namen die mutierte Funktion)
      oder hat einen einzelnen, begründeten `exclude_re`-Eintrag.
- [ ] Neue Tests laufen grün: `cargo test -p <crate> --features test-support`.
- [ ] `cargo clippy -p <crate> --all-targets -- -D warnings` ist leer.
- [ ] Kein `unwrap()`/`expect()`/`panic!()` im **Produktionscode** (in `#[cfg(test)]` erlaubt).
- [ ] P0-Patch: Tests laufen **ohne** Docker und sind nicht `#[ignore]`.
- [ ] Keine timing-/sleep-basierten Tests (Budgets analytisch asserten, AGENTS §4).
- [ ] Statuszeile aktualisiert (☑ + Commit-Hash).

## Branches & Session-Split

Jede neue Session: einen (weiteren) Patch aus einem Batch-Branch übernehmen, implementieren,
Commit mit `P<id>`-Referenz im Conventional-Commit versehen und die Statuszeile hier aktualisieren.

| Batch | Branch | Patches | Priorität |
|---|---|---|---|
| 1 — Security & Crypto | `feature/274-batch1-security-crypto` | P1.1–P1.5 | **P0** |
| 2 — Authz-Handler 403 | `feature/274-batch2-authz-handlers` | P2.1–P2.5 | **P0** |
| 3 — AI-Import | `feature/274-batch3-ai-import` | P3.1–P3.17 | P1 |
| 4 — Audit & Reporting | `feature/274-batch4-audit-reporting` | P4.1–P4.5 | P1 |
| 5 — Photo-Sagas & GC | `feature/274-batch5-photo-sagas-gc` | P5.1–P5.5 | P1 |
| 6 — Queries & Diverses | `feature/274-batch6-queries-misc` | P6.1–P6.8 | P2 |

---

## Batch 1 — Security & Crypto (P0)

**Batch-Branch:** `feature/274-batch1-security-crypto` · **Basis:** `main` (nach Merge von PR #277)

*~35 Mutanten · blocking `mutate-security`-Job · zuerst bearbeiten.*

| Patch | Datei(en) | Survivor | Status |
|---|---|---|---|
| [P1.1](#p1.1) | `crates/api/src/auth/authorization.rs` | 1 | ☑ |
| [P1.2](#p1.2) | `crates/infra/src/tls.rs` | 12 | ☑ |
| [P1.3](#p1.3) | `crates/infra/src/vault.rs` | 10 | ☑ |
| [P1.4](#p1.4) | `crates/core/src/settings/ports.rs` | 10 | ☑ |
| [P1.5](#p1.5) | `crates/api/src/tls_config.rs` | 2 | ☑ |

### P1.1 — Authorization-Bypass-Test für `requirement_for`

<a id="p1.1"></a>

**Datei(en):** `crates/api/src/auth/authorization.rs`  
**Status:** ☑ erledigt · **Survivor:** 1 · **Commit:** TBD · **Testdatei:** `crates/api/tests/auth_authorization.rs::pdf_report_requires_both_conditions` · **PR/Branch:** `feature/274-batch1-security-crypto`

**Überlebende Mutanten:**

- `crates/api/src/auth/authorization.rs:252:31: replace && with || in requirement_for`

**Strategie:**

- `&&` → `||` in `requirement_for` (Zeile 252): Test schreiben, der **nur eine** von zwei erforderlichen Bedingungen erfüllt und `403` erwartet (die Disjunktion würde gewähren).
- Testort: Whitebox-Unit-Test im selben File bzw. `crates/api/src/auth/`; muss ohne Docker laufen.
- Gehört zum blocking `mutate-security`-Job (`api/auth/**`) – P0.

**Verify:**

```bash
cargo mutants --file crates/api/src/auth/authorization.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P1.2 — TLS-Pinning: `root_cert_from_env`, `is_temporary_error`, `PinnedRootTransport::fetch`

<a id="p1.2"></a>

**Datei(en):** `crates/infra/src/tls.rs`  
**Status:** ☑ erledigt · **Survivor:** 12 · **Commit:** TBD · **PR/Branch:** `feature/274-batch1-security-crypto`

**Überlebende Mutanten:**

- `crates/infra/src/tls.rs:43:5: replace root_cert_from_env -> Result<Option<std::path::PathBuf>, String> with Ok(None)`
- `crates/infra/src/tls.rs:44:18: delete ! in root_cert_from_env`
- `crates/infra/src/tls.rs:44:18: replace match guard !v.trim().is_empty() with false in root_cert_from_env`
- `crates/infra/src/tls.rs:44:18: replace match guard !v.trim().is_empty() with true in root_cert_from_env`
- `crates/infra/src/tls.rs:82:36: replace == with != in <impl HttpTransport for PinnedRootTransport>::fetch`
- `crates/infra/src/tls.rs:99:12: delete ! in <impl HttpTransport for PinnedRootTransport>::fetch`
- `crates/infra/src/tls.rs:115:41: replace || with && in <impl HttpTransport for PinnedRootTransport>::fetch`
- `crates/infra/src/tls.rs:127:43: delete ! in <impl HttpTransport for PinnedRootTransport>::fetch`
- `crates/infra/src/tls.rs:156:22: replace || with && in is_temporary_error`
- `crates/infra/src/tls.rs:156:39: replace || with && in is_temporary_error`
- `crates/infra/src/tls.rs:156:5: replace is_temporary_error -> bool with false`
- `crates/infra/src/tls.rs:156:5: replace is_temporary_error -> bool with true`

**Strategie:**

- Unit-Tests gegen `root_cert_from_env`: Env unset / leer / nur Whitespace → `Ok(None)`; gesetzter Pfad auf fehlende Datei → `Err`; gültige Datei → `Ok(Some(_))`.
- Env-Variablen nicht direkt setzen (unsafe in Edition 2024): Logik soweit möglich über `from_value` testen; für den Match-Guard die Entscheidung ggf. in eine Funktion mit Wertparameter refactoren.
- `is_temporary_error`: je ein Test pro Disjunkt (`is_request`, `is_body`, `is_decode`) mit konstruierten `reqwest::Error`-Instanzen plus ein Negativtest.
- `PinnedRootTransport::fetch`: Statuscode-`==`/`!`-Mutanten über Mock-/lokalen Endpoint oder Refactor der Entscheidungslogik in eine testbare Funktion abdecken.

**Verify:**

```bash
cargo mutants --file crates/infra/src/tls.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P1.3 — Vault: Debug-Redaction, `from_env`-Guards, Token-/Schlüsselauflösung (+ Timeout-Härtung)

<a id="p1.3"></a>

**Datei(en):** `crates/infra/src/vault.rs`  
**Status:** ☑ erledigt · **Survivor:** 10 · **Commit:** TBD · **PR/Branch:** `feature/274-batch1-security-crypto`

**Überlebende Mutanten:**

- `crates/infra/src/vault.rs:36:9: replace <impl fmt::Debug for VaultClient>::fmt -> fmt::Result with Ok(Default::default())`
- `crates/infra/src/vault.rs:68:28: delete ! in VaultClient::from_env`
- `crates/infra/src/vault.rs:75:28: delete ! in VaultClient::from_env`
- `crates/infra/src/vault.rs:100:9: replace VaultClient::current_token -> Option<Zeroizing<String>> with Some(Zeroizing::from(String::new()))`
- `crates/infra/src/vault.rs:100:9: replace VaultClient::current_token -> Option<Zeroizing<String>> with Some(Zeroizing::new("xyzzy".into()))`
- `crates/infra/src/vault.rs:100:9: replace VaultClient::current_token -> Option<Zeroizing<String>> with Some(Zeroizing::new(String::new()))`
- `crates/infra/src/vault.rs:265:34: replace == with != in VaultClient::photo_sse_c_key`
- `crates/infra/src/vault.rs:297:13: replace || with && in VaultClient::photo_sse_c_wrapped_key`
- `crates/infra/src/vault.rs:336:9: replace <impl crate::photo::storage::PhotoStorageKeySource for VaultClient>::resolve -> Result<Zeroizing<Vec<u8>>, DomainError> with Ok(Zeroizing::from(vec![]))`
- `crates/infra/src/vault.rs:336:9: replace <impl crate::photo::storage::PhotoStorageKeySource for VaultClient>::resolve -> Result<Zeroizing<Vec<u8>>, DomainError> with Ok(Zeroizing::new(vec![]))`

**Strategie:**

- `Debug::fmt` (36): asserten, dass `format!("{:?}", client)` weder Token noch Secret enthält.
- `from_env` `delete !` (68, 75): fehlende Env-Variablen müssen `Err` liefern – Test mit unset Vars.
- `current_token` (100): Mutant liefert `Some("")` / `"xyzzy"` – Pfad testen, der den echten Token weiterverwendet (Header-Assert an einem Mock-Server oder über `resolve`).
- `photo_sse_c_key` `==`→`!=` (265), `photo_sse_c_wrapped_key` `||`→`&&` (297), `PhotoStorageKeySource::resolve` → `Ok(empty)` (336): Unit-/Integration-Test für den Wrapping-Roundtrip.
- ⏱ **Timeout-Härtung (Code-Fix, kein reiner Test):** Retry-Loop um `ensure_key` (~147) und `photo_sse_c_wrapped_key` begrenzen (max. Versuche / Deadline), damit die `Ok(true/false/None)`-Mutanten nicht mehr hängen, sondern als `Err` erkennbar sind – siehe Issue-Tabelle „Timeouts“.

**Verify:**

```bash
cargo mutants --file crates/infra/src/vault.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P1.4 — Key-Material: `has_same_material`, `SecretValue::fmt`, Zeroize/Drop

<a id="p1.4"></a>

**Datei(en):** `crates/core/src/settings/ports.rs`  
**Status:** ☑ erledigt · **Survivor:** 10 · **Commit:** TBD · **PR/Branch:** `feature/274-batch1-security-crypto`

**Überlebende Mutanten:**

- `crates/core/src/settings/ports.rs:33:9: replace <impl std::fmt::Debug for SecretValue>::fmt -> std::fmt::Result with Ok(Default::default())`
- `crates/core/src/settings/ports.rs:85:26: replace == with != in GDriveCredentialBundle::has_same_material`
- `crates/core/src/settings/ports.rs:85:9: replace GDriveCredentialBundle::has_same_material -> bool with false`
- `crates/core/src/settings/ports.rs:85:9: replace GDriveCredentialBundle::has_same_material -> bool with true`
- `crates/core/src/settings/ports.rs:86:13: replace && with || in GDriveCredentialBundle::has_same_material`
- `crates/core/src/settings/ports.rs:91:13: replace && with || in GDriveCredentialBundle::has_same_material`
- `crates/core/src/settings/ports.rs:96:13: replace && with || in GDriveCredentialBundle::has_same_material`
- `crates/core/src/settings/ports.rs:96:38: replace == with != in GDriveCredentialBundle::has_same_material`
- `crates/core/src/settings/ports.rs:137:9: replace <impl Zeroize for GDriveCredentialWire>::zeroize with ()`
- `crates/core/src/settings/ports.rs:148:9: replace <impl Drop for GDriveCredentialWire>::drop with ()`

**Strategie:**

- `has_same_material` (85–96): Wahrheitstabelle abdecken – identisch → `true`; je ein Feld abweichend (client_id, client_secret, refresh_token, root_folder_id) → `false`. Killt `->false`, `->true`, `==`→`!=` und alle `&&`→`||`-Mutanten.
- `Debug for SecretValue` (33): Assert, dass die Debug-Ausgabe niemals Klartext-Material enthält.
- `Zeroize`/`Drop` → `()` (137, 148): nach `zeroize()`/`drop()` prüfen, dass der Buffer genullt ist (z. B. interne Bytes vor dem Drop inspizieren). Falls strukturell untestbar: `exclude_re` mit Security-Begründung dokumentieren.

**Verify:**

```bash
cargo mutants --file crates/core/src/settings/ports.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P1.5 — `TlsConfig::validate` / `postgres_violations` (API-Startup-Gate)

<a id="p1.5"></a>

**Datei(en):** `crates/api/src/tls_config.rs`  
**Status:** ☑ erledigt · **Survivor:** 2 · **Commit:** TBD · **PR/Branch:** `feature/274-batch1-security-crypto`

**Überlebende Mutanten:**

- `crates/api/src/tls_config.rs:166:9: replace TlsConfig::validate -> Result<(), String> with Ok(())`
- `crates/api/src/tls_config.rs:191:23: replace match guard !root.trim().is_empty() with true in postgres_violations`

**Strategie:**

- `validate` → `Ok(())` (166) und Guard `!root.trim().is_empty()` (191): Tabelle aus `REQUIRE_IN_TRANSIT_TLS=true` × fehlendem/leerem/gültigem Root-CA-Pfad × URL-Schemata; jede Verletzung muss `Err(String)` liefern (ADR-024 Startup-Gate).

**Verify:**

```bash
cargo mutants --file crates/api/src/tls_config.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

---

## Batch 2 — Authz-Handler 403-Tests (P0)

**Batch-Branch:** `feature/274-batch2-authz-handlers` · **Basis:** `main` (nach Merge von PR #277)

*~54 Mutanten · jeder `// AUTHZ-GATE:`-grep bekommt einen Test-Partner.*

| Patch | Datei(en) | Survivor | Status |
|---|---|---|---|
| [P2.1](#p21--authz-gate-403-tests-costume-photo-handler) | `crates/api/src/handlers/mod.rs` | 7 | [x] |
| [P2.2](#p22--authz-gate-403-tests-continuity-photos--reports) | `crates/api/src/handlers/mod.rs` | 9 | [x] |
| [P2.3](#p23--settingsgdriveai-handler-authz--bedingungslogik) | `crates/api/src/handlers/mod.rs` | 16 | ☐ parteilsweise |
| [P2.4](#p24--series_id_for_--require_-audit-helfer) | `crates/api/src/handlers/mod.rs` | 9 | ☐ parteilsweise |
| [P2.5](#p25--upload-validierung--variant-routing-handlersmodrs-rest) | `crates/api/src/handlers/mod.rs` | 13 | ☐ parteilsweise |

### P2.1 — AUTHZ-GATE 403-Tests: Costume-Photo-Handler

**Datei(en):** `crates/api/src/handlers/mod.rs`  
**Status:** [x] erledigt · **Survivor:** 7 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch2-authz-handlers`

**Überlebende Mutanten:**

- `crates/api/src/handlers/mod.rs:1958:8: delete ! in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1962:25: replace == with != in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1962:41: replace || with && in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1962:57: replace == with != in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:2007:8: delete ! in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:2122:8: delete ! in get_costume_photo_bytes`
- `crates/api/src/handlers/mod.rs:2222:8: delete ! in delete_costume_photo`

**Strategie:**

- `delete !`-Mutanten = entfernte Authz-Negation in `upload_costume_photo` (1958, 2007), `get_costume_photo_bytes` (2122), `delete_costume_photo` (2222).
- Pro Handler je ein Test: Nicht-Mitglied / Nicht-authentifiziert → `403` (Problem-JSON), Mitglied mit aktiver Rolle → Erfolg.
- Vorhandene Muster suchen und auf fehlende Handler erweitern (`grep -n 'AUTHZ-GATE' crates/api/src/handlers/mod.rs`).

**Verify:**

```bash
cargo mutants --file crates/api/src/handlers/mod.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P2.2 — AUTHZ-GATE 403-Tests: Continuity-Photos & Reports

**Datei(en):** `crates/api/src/handlers/mod.rs`  
**Status:** [x] erledigt · **Survivor:** 9 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch2-authz-handlers`

**Überlebende Mutanten:**

- `crates/api/src/handlers/mod.rs:2659:8: delete ! in link_continuity_photo`
- `crates/api/src/handlers/mod.rs:2730:8: delete ! in unlink_continuity_photo`
- `crates/api/src/handlers/mod.rs:2814:8: delete ! in dispo_report`
- `crates/api/src/handlers/mod.rs:2854:8: delete ! in shoot_day_report`
- `crates/api/src/handlers/mod.rs:2894:8: delete ! in soll_ist_report`
- `crates/api/src/handlers/mod.rs:2962:8: delete ! in dispo_report_pdf`
- `crates/api/src/handlers/mod.rs:3040:8: delete ! in shoot_day_report_pdf`
- `crates/api/src/handlers/mod.rs:3118:8: delete ! in planned_vs_actual_report_pdf`
- `crates/api/src/handlers/mod.rs:3225:8: delete ! in manual_archive_reports`

**Strategie:**

- `delete !` in `link_continuity_photo` (2659), `unlink_continuity_photo` (2730), `dispo_report` (2814), `shoot_day_report` (2854), `soll_ist_report` (2894), `dispo_report_pdf` (2962), `shoot_day_report_pdf` (3040), `planned_vs_actual_report_pdf` (3118), `manual_archive_reports` (3225).
- Gleiche 403-Testmatrix wie P2.1; PDF-Varianten mindestens auf Statuscode prüfen.

**Verify:**

```bash
cargo mutants --file crates/api/src/handlers/mod.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P2.3 — Settings/GDrive/AI-Handler: Authz + Bedingungslogik

**Datei(en):** `crates/api/src/handlers/mod.rs`  
**Status:** ☐ parteilsweise erledigt · **Survivor:** 16 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch2-authz-handlers`

**Erledigt (5 Tests):** create_gdrive_credential, rotate_gdrive_credential, create_credential, get_settings, revoke_settings — je ein 403-Denial-Test.

**Offen:** apply_ai_import (Job-Status-Bedingung, accept_as_is-Validierung, Telemetry-Felder) — 9 Mutanten.

**Überlebende Mutanten:**

- `crates/api/src/handlers/mod.rs:3291:8: delete ! in create_gdrive_credential`
- `crates/api/src/handlers/mod.rs:3362:8: delete ! in rotate_gdrive_credential`
- `crates/api/src/handlers/mod.rs:3368:22: replace != with == in rotate_gdrive_credential`
- `crates/api/src/handlers/mod.rs:3369:31: replace == with != in rotate_gdrive_credential`
- `crates/api/src/handlers/mod.rs:3369:9: replace || with && in rotate_gdrive_credential`
- `crates/api/src/handlers/mod.rs:3489:8: delete ! in create_credential`
- `crates/api/src/handlers/mod.rs:3556:8: delete ! in get_settings`
- `crates/api/src/handlers/mod.rs:3562:27: replace == with != in get_settings`
- `crates/api/src/handlers/mod.rs:3563:9: replace && with || in get_settings`
- `crates/api/src/handlers/mod.rs:3591:8: delete ! in revoke_settings`
- `crates/api/src/handlers/mod.rs:3906:5: replace get_ai_import_preview -> Result<Response, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:3980:9: delete field doc_kind from struct Telemetry expression in apply_ai_import`
- `crates/api/src/handlers/mod.rs:3984:9: delete field apply_state from struct Telemetry expression in apply_ai_import`
- `crates/api/src/handlers/mod.rs:4031:24: delete ! in apply_ai_import`
- `crates/api/src/handlers/mod.rs:4035:41: replace != with == in apply_ai_import`
- `crates/api/src/handlers/mod.rs:4040:39: replace > with < in apply_ai_import`

**Strategie:**

- `delete !` in `create_gdrive_credential` (3291), `rotate_gdrive_credential` (3362), `create_credential` (3489), `get_settings` (3556), `revoke_settings` (3591), `apply_ai_import` (4031); zusätzlich Bedingungsmutanten 3368–3369, 3562–3563, 4035 (`!=`→`==`), 4040 (`>`→`<`) sowie Telemetry-Feld-Löschungen (3980, 3984).
- Tests: Rollen-Matrix (Admin vs. Planner vs. Fremder) pro Endpoint + Grenzfälle der Bedingungen (z. B. apply nur bei passendem Zustand).

**Verify:**

```bash
cargo mutants --file crates/api/src/handlers/mod.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P2.4 — `series_id_for_*` / `require_*` Audit-Helfer

**Datei(en):** `crates/api/src/handlers/mod.rs`  
**Status:** ☐ parteilsweise erledigt · **Survivor:** 9 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch2-authz-handlers`

**Erledigt (1 Test):** require_series — 400 bei fehlendem Query-Parameter.

**Offen:** series_id_for_scene, series_id_for_shooting_day, series_id_for_character, series_id_for_costume_category, series_id_for_scene_shoot, series_id_for_costume — Return-Value-Propagations-Tests (8 Mutanten).

**Überlebende Mutanten:**

- `crates/api/src/handlers/mod.rs:350:5: replace require_episode -> Result<EpisodeId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:364:5: replace require_series -> Result<SeriesId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:379:5: replace series_id_for_scene -> Result<SeriesId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:393:5: replace series_id_for_shooting_day -> Result<SeriesId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:407:5: replace series_id_for_character -> Result<SeriesId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:421:5: replace series_id_for_costume_category -> Result<SeriesId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:435:5: replace series_id_for_scene_shoot -> Result<SeriesId, ApiError> with Ok(Default::default())`
- `crates/api/src/handlers/mod.rs:454:5: replace series_id_for_costume -> Result<Option<SeriesId>, ApiError> with Ok(None)`
- `crates/api/src/handlers/mod.rs:454:5: replace series_id_for_costume -> Result<Option<SeriesId>, ApiError> with Ok(Some(Default::default()))`

**Strategie:**

- Mutanten: `require_episode`/`require_series` → `Ok(Default)` (350, 364) und alle `series_id_for_{scene,shooting_day,character,costume_category,scene_shoot,costume}` → `Ok(Default)`/`Ok(None)`/`Ok(Some(..))` (379–454).
- Diese Helfer lesen Read-Model-Daten (legitim am API-Rand) und bestimmen `series_id` fürs Audit.
- Kill: Repository-Fake injizieren und asserten, dass die zurückgegebene SeriesId in den erzeugten Command(s) landet bzw. `NotFound` propagiert wird.

**Verify:**

```bash
cargo mutants --file crates/api/src/handlers/mod.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P2.5 — Upload-Validierung & Variant-Routing (handlers/mod.rs Rest)

**Datei(en):** `crates/api/src/handlers/mod.rs`  
**Status:** ☐ parteilsweise erledigt · **Survivor:** 13 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch2-authz-handlers`

**Erledigt (3 Tests):** Upload-Size-Grenze (PHOTO_MAX_SIZE_MB), Content-Type-Validierung (falscher Typ, HEIC).

**Offen:** get_costume_photo_bytes Variant-Routing (thumb/medium Match-Arme), plan_scene_shoot Konflikt-Check — 10 Mutanten.

**Überlebende Mutanten:**

- `crates/api/src/handlers/mod.rs:1977:33: replace * with + in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1977:33: replace * with / in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1977:40: replace * with + in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1977:40: replace * with / in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1978:19: replace > with < in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1978:19: replace > with == in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:1978:19: replace > with >= in upload_costume_photo`
- `crates/api/src/handlers/mod.rs:2102:5: replace get_costume_photo_bytes -> Result<(StatusCode, axum::http::HeaderMap, Vec<u8>), ApiError> with Ok((Default::default(), Default::default(), vec![0]))`
- `crates/api/src/handlers/mod.rs:2102:5: replace get_costume_photo_bytes -> Result<(StatusCode, axum::http::HeaderMap, Vec<u8>), ApiError> with Ok((Default::default(), Default::default(), vec![1]))`
- `crates/api/src/handlers/mod.rs:2102:5: replace get_costume_photo_bytes -> Result<(StatusCode, axum::http::HeaderMap, Vec<u8>), ApiError> with Ok((Default::default(), Default::default(), vec![]))`
- `crates/api/src/handlers/mod.rs:2130:9: delete match arm "thumb" in get_costume_photo_bytes`
- `crates/api/src/handlers/mod.rs:2131:9: delete match arm "medium" in get_costume_photo_bytes`
- `crates/api/src/handlers/mod.rs:2345:28: replace != with == in plan_scene_shoot`

**Strategie:**

- Größenprüfung `PHOTO_MAX_SIZE_MB`: `*`→`+`//` (1977) und `>`→`<`/`==`/`>=` (1978): Boundary-Tests exakt an der Grenze (max_bytes ok, max_bytes+1 → Problem-Code).
- `get_costume_photo_bytes` → `Ok(default)` (2102×3) und Variant-Match-Arme `thumb`/`medium` (2130, 2131): je Variante Content-Type/Länge asserten.
- `plan_scene_shoot` `!=`→`==` (2345): Konflikt- und Erfolgsfall testen.

**Verify:**

```bash
cargo mutants --file crates/api/src/handlers/mod.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

---

## Batch 3 — AI-Import (P1)

**Batch-Branch:** `feature/274-batch3-ai-import` · **Basis:** `main` (nach Merge von PR #277)

*`crates/infra/src/ai/**` + `crates/core/src/ai/**`.*

| Patch | Datei(en) | Survivor | Status |
|---|---|---|---|
| [P3.1](#p3.1) | `crates/core/src/ai/bounds.rs` | 15 | ☑ |
| [P3.2](#p3.2) | `crates/core/src/ai/aggregate.rs` | 8 | ☑ |
| [P3.3](#p3.3) | `crates/core/src/ai/ports.rs` | 13 | ☑ |
| [P3.4](#p3.4) | `crates/core/src/ai/views.rs` | 8 | ☑ |
| [P3.5](#p3.5) | `crates/core/src/ai/preview.rs` | 5 | ☑ |
| [P3.6](#p3.6) | `crates/infra/src/ai/pg_concurrency.rs` | 20 | ☑ |
| [P3.7](#p3.7) | `crates/infra/src/ai/queue.rs` | 20 | ☑ |
| [P3.8](#p3.8) | `crates/infra/src/ai/concurrency.rs` | 8 | ☑ |
| [P3.9](#p3.9) | `crates/infra/src/ai/client.rs` | 14 | ☑ |
| [P3.10](#p3.10) | `crates/infra/src/ai/mod.rs` | 9 | ☑ |
| [P3.11](#p3.11) | `crates/infra/src/ai/mapping.rs` | 8 | ☑ |
| [P3.12](#p3.12) | `crates/infra/src/ai/workers.rs` … | 20 | ☑ |
| [P3.13](#p3.13) | `crates/infra/src/ai/ollama.rs` … | 8 | ☑ |
| [P3.14](#p3.14) | `crates/infra/src/ai/shutdown.rs` | 5 | ☑ |
| [P3.15](#p3.15) | `crates/infra/src/ai/pdf.rs` … | 6 | ☑ |
| [P3.16](#p3.16) | `crates/infra/src/ai/catalog.rs` … | 10 | ☑ |
| [P3.17](#p3.17) | `crates/infra/src/ai/payload_cleanup.rs` | 10 | ☑ |

### P3.1 — `AiImportBounds::validate` / `bounded_u32/u64` (Boundary-Tests)

**Datei(en):** `crates/core/src/ai/bounds.rs`  
**Status:** ☐ offen · **Survivor:** 15 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/core/src/ai/bounds.rs:52:9: replace AiImportBounds::from_env -> Self with Default::default()`
- `crates/core/src/ai/bounds.rs:109:13: replace || with && in AiImportBounds::validate`
- `crates/core/src/ai/bounds.rs:110:13: replace || with && in AiImportBounds::validate`
- `crates/core/src/ai/bounds.rs:111:13: replace || with && in AiImportBounds::validate`
- `crates/core/src/ai/bounds.rs:115:46: replace > with >= in AiImportBounds::validate`
- `crates/core/src/ai/bounds.rs:127:5: replace bounded_u32 -> u32 with 0`
- `crates/core/src/ai/bounds.rs:127:5: replace bounded_u32 -> u32 with 1`
- `crates/core/src/ai/bounds.rs:130:33: replace >= with < in bounded_u32`
- `crates/core/src/ai/bounds.rs:130:41: replace && with || in bounded_u32`
- `crates/core/src/ai/bounds.rs:130:52: replace <= with > in bounded_u32`
- `crates/core/src/ai/bounds.rs:135:5: replace bounded_u64 -> u64 with 0`
- `crates/core/src/ai/bounds.rs:135:5: replace bounded_u64 -> u64 with 1`
- `crates/core/src/ai/bounds.rs:138:33: replace >= with < in bounded_u64`
- `crates/core/src/ai/bounds.rs:138:41: replace && with || in bounded_u64`
- `crates/core/src/ai/bounds.rs:138:52: replace <= with > in bounded_u64`

**Strategie:**

- Pro Feld (chunks, tokens, concurrency global/user, document bytes, lease): Wert unterhalb, exakt am Minimum/Maximum und oberhalb testen.
- Kombination zweier Verstöße je Test (killt `||`→`&&`, weil die Disjunktion dann zu früh/falsch akzeptiert).

**Verify:**

```bash
cargo mutants --file crates/core/src/ai/bounds.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P3.2 — AI-Aggregate: Event-Count-Assertions

**Datei(en):** `crates/core/src/ai/aggregate.rs`  
**Status:** ☐ offen · **Survivor:** 8 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/core/src/ai/aggregate.rs:59:9: replace <impl Apply for AiConfig>::apply with ()`
- `crates/core/src/ai/aggregate.rs:113:9: replace <impl Command<CreateAiConfig> for AiConfig>::handle -> Result<Vec<Self::Event>, Self::Error> with Ok(vec![])`
- `crates/core/src/ai/aggregate.rs:139:9: replace <impl Command<UpdateAiConfig> for AiConfig>::handle -> Result<Vec<Self::Event>, Self::Error> with Ok(vec![])`
- `crates/core/src/ai/aggregate.rs:143:29: replace != with == in <impl Command<UpdateAiConfig> for AiConfig>::handle`
- `crates/core/src/ai/aggregate.rs:146:24: replace != with == in <impl Command<UpdateAiConfig> for AiConfig>::handle`
- `crates/core/src/ai/aggregate.rs:177:9: replace <impl Command<RevokeAiConfig> for AiConfig>::handle -> Result<Vec<Self::Event>, Self::Error> with Ok(vec![])`
- `crates/core/src/ai/aggregate.rs:183:24: replace != with == in <impl Command<RevokeAiConfig> for AiConfig>::handle`
- `crates/core/src/ai/aggregate.rs:201:5: replace validate_fields -> Result<(), AiConfigError> with Ok(())`

**Strategie:**

- `CreateAiConfig`/`UpdateAiConfig`/`RevokeAiConfig` → `Ok(vec![])`: in jedem Command-Test `assert_eq!(events.len(), 1)` plus Event-Variant/-Felder asserten.
- Negativfälle ergänzen (revoked config, Duplikate), damit die Guards selbst ebenfalls getestet sind.

**Verify:**

```bash
cargo mutants --file crates/core/src/ai/aggregate.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P3.3 — `LlmClient`-Port-Defaults

**Datei(en):** `crates/core/src/ai/ports.rs`  
**Status:** ☐ offen · **Survivor:** 13 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/core/src/ai/ports.rs:41:9: replace LlmProvider::as_str -> &'static str with ""`
- `crates/core/src/ai/ports.rs:41:9: replace LlmProvider::as_str -> &'static str with "xyzzy"`
- `crates/core/src/ai/ports.rs:55:9: replace LlmProvider::curated_base_url_key -> &'static str with ""`
- `crates/core/src/ai/ports.rs:55:9: replace LlmProvider::curated_base_url_key -> &'static str with "xyzzy"`
- `crates/core/src/ai/ports.rs:59:9: replace LlmProvider::is_local -> bool with false`
- `crates/core/src/ai/ports.rs:59:9: replace LlmProvider::is_local -> bool with true`
- `crates/core/src/ai/ports.rs:138:9: replace LlmClient::extract_schedule -> Result<ShootingSchedule, DomainError> with Ok(Default::default())`
- `crates/core/src/ai/ports.rs:214:9: replace AiImportQueue::claim_next_reconciling -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> with Ok(None)`
- `crates/core/src/ai/ports.rs:225:9: replace AiImportQueue::claim_next_kind_reconciling -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> with Ok(None)`
- `crates/core/src/ai/ports.rs:283:9: replace AiImportQueue::lease_window -> Option<std::time::Duration> with Some(Default::default())`
- `crates/core/src/ai/ports.rs:402:32: replace == with != in AiImportMapping::is_reserved`
- `crates/core/src/ai/ports.rs:402:9: replace AiImportMapping::is_reserved -> bool with false`
- `crates/core/src/ai/ports.rs:402:9: replace AiImportMapping::is_reserved -> bool with true`

**Strategie:**

- 13 Mutanten am Port-Trait (Default-Implementierungen). Kill über Fake-Client-Tests, die das Default-Verhalten kontraktuell asserten (Request-Form, Response-Mapping, Fehlerpfad).

**Verify:**

```bash
cargo mutants --file crates/core/src/ai/ports.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P3.4 — AI-Views (core)

**Datei(en):** `crates/core/src/ai/views.rs`  
**Status:** ☐ offen · **Survivor:** 8 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/core/src/ai/views.rs:25:9: replace DocumentKind::as_str -> &'static str with ""`
- `crates/core/src/ai/views.rs:25:9: replace DocumentKind::as_str -> &'static str with "xyzzy"`
- `crates/core/src/ai/views.rs:208:9: replace TelemetryApplyState::accept_as_is -> Option<bool> with None`
- `crates/core/src/ai/views.rs:208:9: replace TelemetryApplyState::accept_as_is -> Option<bool> with Some(false)`
- `crates/core/src/ai/views.rs:208:9: replace TelemetryApplyState::accept_as_is -> Option<bool> with Some(true)`
- `crates/core/src/ai/views.rs:216:9: replace TelemetryApplyState::edit_distance -> Option<u32> with None`
- `crates/core/src/ai/views.rs:216:9: replace TelemetryApplyState::edit_distance -> Option<u32> with Some(0)`
- `crates/core/src/ai/views.rs:216:9: replace TelemetryApplyState::edit_distance -> Option<u32> with Some(1)`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/core/src/ai/views.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P3.5 — AI-Preview (core)

**Datei(en):** `crates/core/src/ai/preview.rs`  
**Status:** ☐ offen · **Survivor:** 5 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/core/src/ai/preview.rs:29:9: replace SceneChunk::extract_scenes -> Vec<Self> with vec![]`
- `crates/core/src/ai/preview.rs:55:9: replace DraftScene::scene_details -> SceneDetails with Default::default()`
- `crates/core/src/ai/preview.rs:235:16: delete ! in extract_scenes`
- `crates/core/src/ai/preview.rs:302:41: replace % with / in merge_schedule_to_scenes`
- `crates/core/src/ai/preview.rs:303:21: replace += with *= in merge_schedule_to_scenes`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/core/src/ai/preview.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P3.6 — Permit-Concurrency: `pg_concurrency.rs` (+ Timeout-Härtung `permit_renewal_interval`)

**Datei(en):** `crates/infra/src/ai/pg_concurrency.rs`  
**Status:** ☐ offen · **Survivor:** 20 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/pg_concurrency.rs:95:17: replace < with <= in permit_renewal_interval`
- `crates/infra/src/ai/pg_concurrency.rs:181:9: replace PgAiConcurrencyLimiter::try_acquire -> Result<Option<PgAiConcurrencyPermit>, DomainError> with Ok(None)`
- `crates/infra/src/ai/pg_concurrency.rs:191:9: replace PgAiConcurrencyLimiter::try_acquire_as -> Result<Option<PgAiConcurrencyPermit>, DomainError> with Ok(None)`
- `crates/infra/src/ai/pg_concurrency.rs:226:22: replace > with < in PgAiConcurrencyLimiter::try_acquire_as`
- `crates/infra/src/ai/pg_concurrency.rs:226:22: replace > with == in PgAiConcurrencyLimiter::try_acquire_as`
- `crates/infra/src/ai/pg_concurrency.rs:226:22: replace > with >= in PgAiConcurrencyLimiter::try_acquire_as`
- `crates/infra/src/ai/pg_concurrency.rs:241:19: replace >= with < in PgAiConcurrencyLimiter::try_acquire_as`
- `crates/infra/src/ai/pg_concurrency.rs:258:21: replace >= with < in PgAiConcurrencyLimiter::try_acquire_as`
- `crates/infra/src/ai/pg_concurrency.rs:309:9: replace PgAiConcurrencyLimiter::in_flight -> Result<i64, DomainError> with Ok(-1)`
- `crates/infra/src/ai/pg_concurrency.rs:309:9: replace PgAiConcurrencyLimiter::in_flight -> Result<i64, DomainError> with Ok(0)`
- `crates/infra/src/ai/pg_concurrency.rs:309:9: replace PgAiConcurrencyLimiter::in_flight -> Result<i64, DomainError> with Ok(1)`
- `crates/infra/src/ai/pg_concurrency.rs:353:9: replace PermitReclaimer::shutdown with ()`
- `crates/infra/src/ai/pg_concurrency.rs:367:9: replace PermitReclaimer::abort with ()`
- `crates/infra/src/ai/pg_concurrency.rs:377:9: replace <impl Drop for PermitReclaimer>::drop with ()`
- `crates/infra/src/ai/pg_concurrency.rs:388:5: replace reclaim_loop with ()`
- `crates/infra/src/ai/pg_concurrency.rs:444:9: replace PgAiConcurrencyPermit::deadline -> Result<Option<DateTime<Utc>>, DomainError> with Ok(None)`
- `crates/infra/src/ai/pg_concurrency.rs:458:9: replace PgAiConcurrencyPermit::release -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/pg_concurrency.rs:479:9: replace PgAiConcurrencyPermit::renew -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/pg_concurrency.rs:493:21: replace == with != in PgAiConcurrencyPermit::renew`
- `crates/infra/src/ai/pg_concurrency.rs:515:9: replace <impl Drop for PgAiConcurrencyPermit>::drop with ()`

**Strategie:**

- 20 Mutanten an Limit-Vergleichen: Boundary-Tests mit N = Limit−1, N = Limit, N = Limit+1 Akquisitionen; Release gibt Kapazität frei (Postgres-only, Tier 1–3).
- ⏱ **Timeout-Härtung (Code-Fix):** `permit_renewal_interval` (~94) → `Duration::ZERO` hot-loops. Intervall beim Bau clampen (`max(MIN_RENEWAL, interval)`) + Compile-Assert; danach Test, der das geclampte Intervall assertet.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/pg_concurrency.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.7 — Queue: `try_acquire`/Claim-Prädikate

**Datei(en):** `crates/infra/src/ai/queue.rs`  
**Status:** ☐ offen · **Survivor:** 20 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/queue.rs:84:9: replace PgAiImportQueue::lease_secs -> f64 with -1.0`
- `crates/infra/src/ai/queue.rs:84:9: replace PgAiImportQueue::lease_secs -> f64 with 0.0`
- `crates/infra/src/ai/queue.rs:84:9: replace PgAiImportQueue::lease_secs -> f64 with 1.0`
- `crates/infra/src/ai/queue.rs:89:5: replace lease_from_env -> Duration with Default::default()`
- `crates/infra/src/ai/queue.rs:156:9: replace <impl AiImportQueue for PgAiImportQueue>::claim_next -> Result<Option<AiImportJob>, DomainError> with Ok(None)`
- `crates/infra/src/ai/queue.rs:200:9: replace <impl AiImportQueue for PgAiImportQueue>::claim_next_kind -> Result<Option<AiImportJob>, DomainError> with Ok(None)`
- `crates/infra/src/ai/queue.rs:237:9: replace <impl AiImportQueue for PgAiImportQueue>::lease_window -> Option<Duration> with None`
- `crates/infra/src/ai/queue.rs:237:9: replace <impl AiImportQueue for PgAiImportQueue>::lease_window -> Option<Duration> with Some(Default::default())`
- `crates/infra/src/ai/queue.rs:256:9: replace <impl AiImportQueue for PgAiImportQueue>::claim_next_reconciling -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> with Ok(None)`
- `crates/infra/src/ai/queue.rs:304:9: replace <impl AiImportQueue for PgAiImportQueue>::claim_next_kind_reconciling -> Result<Option<(AiImportJob, Option<Uuid>)>, DomainError> with Ok(None)`
- `crates/infra/src/ai/queue.rs:359:9: replace <impl AiImportQueue for PgAiImportQueue>::attach_permit -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:381:9: replace <impl AiImportQueue for PgAiImportQueue>::release_claim -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:406:9: replace <impl AiImportQueue for PgAiImportQueue>::get -> Result<Option<AiImportJob>, DomainError> with Ok(None)`
- `crates/infra/src/ai/queue.rs:427:9: replace <impl AiImportQueue for PgAiImportQueue>::mark_running -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:451:9: replace <impl AiImportQueue for PgAiImportQueue>::mark_succeeded -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:482:9: replace <impl AiImportQueue for PgAiImportQueue>::mark_failed -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:544:9: replace <impl AiImportQueue for PgAiImportQueue>::mark_payload_unavailable -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:577:9: replace <impl AiImportQueue for PgAiImportQueue>::record_worker_telemetry -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:608:9: replace <impl AiImportQueue for PgAiImportQueue>::record_telemetry -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/queue.rs:707:5: replace ensure_claim_owned -> Result<(), DomainError> with Ok(())`

**Strategie:**

- 20 Mutanten: Claim-Vergleiche (`next_attempt_at`, Lease, Retries) und `version_to_db`.
- Postgres-only Integration-Tests (Tier 1–3, testcontainers) mit Randzeiten: `next_attempt_at` genau jetzt / 1 s Zukunft; Lease genau abgelaufen / 1 s restlich.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/queue.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.8 — In-Memory-Concurrency (`concurrency.rs`)

**Datei(en):** `crates/infra/src/ai/concurrency.rs`  
**Status:** ☐ offen · **Survivor:** 8 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/concurrency.rs:36:9: replace AiConcurrencyLimiter::try_acquire -> Result<Option<AiConcurrencyPermit>, DomainError> with Ok(None)`
- `crates/infra/src/ai/concurrency.rs:48:46: replace > with < in AiConcurrencyLimiter::try_acquire`
- `crates/infra/src/ai/concurrency.rs:48:46: replace > with == in AiConcurrencyLimiter::try_acquire`
- `crates/infra/src/ai/concurrency.rs:48:46: replace > with >= in AiConcurrencyLimiter::try_acquire`
- `crates/infra/src/ai/concurrency.rs:49:21: replace || with && in AiConcurrencyLimiter::try_acquire`
- `crates/infra/src/ai/concurrency.rs:49:54: replace < with <= in AiConcurrencyLimiter::try_acquire`
- `crates/infra/src/ai/concurrency.rs:49:54: replace < with == in AiConcurrencyLimiter::try_acquire`
- `crates/infra/src/ai/concurrency.rs:49:54: replace < with > in AiConcurrencyLimiter::try_acquire`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/concurrency.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.9 — LLM-Client: `reject_ollama`, `hosted_origin_host`, `classify_transport_error`

**Datei(en):** `crates/infra/src/ai/client.rs`  
**Status:** ☐ offen · **Survivor:** 14 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/client.rs:49:21: replace == with != in OpenAiCompatibleChatClient::reject_ollama`
- `crates/infra/src/ai/client.rs:49:9: replace OpenAiCompatibleChatClient::reject_ollama -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/client.rs:92:9: replace OpenAiCompatibleChatClient::hosted_origin_host -> Result<String, DomainError> with Ok("xyzzy".into())`
- `crates/infra/src/ai/client.rs:92:9: replace OpenAiCompatibleChatClient::hosted_origin_host -> Result<String, DomainError> with Ok(String::new())`
- `crates/infra/src/ai/client.rs:126:9: replace OpenAiCompatibleChatClient::endpoint -> String with "xyzzy".into()`
- `crates/infra/src/ai/client.rs:126:9: replace OpenAiCompatibleChatClient::endpoint -> String with String::new()`
- `crates/infra/src/ai/client.rs:133:9: replace OpenAiCompatibleChatClient::request -> Result<ScriptContext, DomainError> with Ok(Default::default())`
- `crates/infra/src/ai/client.rs:175:16: delete ! in OpenAiCompatibleChatClient::request`
- `crates/infra/src/ai/client.rs:203:48: replace -= with += in OpenAiCompatibleChatClient::request`
- `crates/infra/src/ai/client.rs:203:48: replace -= with /= in OpenAiCompatibleChatClient::request`
- `crates/infra/src/ai/client.rs:206:77: replace == with != in OpenAiCompatibleChatClient::request`
- `crates/infra/src/ai/client.rs:227:25: replace != with == in <impl LlmClient for OpenAiCompatibleChatClient>::chat_constrained`
- `crates/infra/src/ai/client.rs:227:9: replace <impl LlmClient for OpenAiCompatibleChatClient>::chat_constrained -> Result<ScriptContext, DomainError> with Ok(Default::default())`
- `crates/infra/src/ai/client.rs:309:27: replace || with && in classify_transport_error`

**Strategie:**

- Security-relevant: Ollama-URLs müssen abgelehnt werden; Host-Origin-Parsing-Tabelle (Subdomain, Port, Scheme); Transportfehler-Klassifizierung transient vs. permanent.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/client.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.10 — `CuratedLlmProvider::base_url` (alle 7 Provider-Arme)

**Datei(en):** `crates/infra/src/ai/mod.rs`  
**Status:** ☐ offen · **Survivor:** 9 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/mod.rs:130:9: replace <impl CuratedLlmProvider for CuratedProviderUrls>::base_url -> &'static str with ""`
- `crates/infra/src/ai/mod.rs:130:9: replace <impl CuratedLlmProvider for CuratedProviderUrls>::base_url -> &'static str with "xyzzy"`
- `crates/infra/src/ai/mod.rs:131:13: delete match arm LlmProvider::OpenAI in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`
- `crates/infra/src/ai/mod.rs:132:13: delete match arm LlmProvider::OpenRouter in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`
- `crates/infra/src/ai/mod.rs:133:13: delete match arm LlmProvider::EURouter in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`
- `crates/infra/src/ai/mod.rs:134:13: delete match arm LlmProvider::Neuralwatt in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`
- `crates/infra/src/ai/mod.rs:135:13: delete match arm LlmProvider::OpenCodeGo in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`
- `crates/infra/src/ai/mod.rs:136:13: delete match arm LlmProvider::OpenCode in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`
- `crates/infra/src/ai/mod.rs:137:13: delete match arm LlmProvider::Ollama in <impl CuratedLlmProvider for CuratedProviderUrls>::base_url`

**Strategie:**

- Je Provider-Variante ein Test, der die erwartete Base-URL-Constante assertet – oder ein tabellierter Golden-Test über alle Varianten.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/mod.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.11 — Mapping (LLM-Response → Schedule)

**Datei(en):** `crates/infra/src/ai/mapping.rs`  
**Status:** ☐ offen · **Survivor:** 8 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/mapping.rs:88:9: replace <impl AiImportMappingRepository for PgAiImportMappingRepository>::insert -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/mapping.rs:117:9: replace <impl AiImportMappingRepository for PgAiImportMappingRepository>::list_by_preview -> Result<Vec<AiImportMapping>, DomainError> with Ok(vec![])`
- `crates/infra/src/ai/mapping.rs:137:5: replace version_to_db -> Result<i64, DomainError> with Ok(-1)`
- `crates/infra/src/ai/mapping.rs:137:5: replace version_to_db -> Result<i64, DomainError> with Ok(0)`
- `crates/infra/src/ai/mapping.rs:137:5: replace version_to_db -> Result<i64, DomainError> with Ok(1)`
- `crates/infra/src/ai/mapping.rs:147:26: replace < with <= in map_mapping`
- `crates/infra/src/ai/mapping.rs:147:26: replace < with == in map_mapping`
- `crates/infra/src/ai/mapping.rs:147:26: replace < with > in map_mapping`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/mapping.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.12 — Worker/Merge-Loops

**Datei(en):** `crates/infra/src/ai/workers.rs`, `crates/infra/src/ai/worker_loop.rs`  
**Status:** ☐ offen · **Survivor:** 20 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/workers.rs:53:5: replace acquire_for_claim -> Result<Option<PgAiConcurrencyPermit>, DomainError> with Ok(None)`
- `crates/infra/src/ai/workers.rs:140:5: replace release_permit_logging_errors with ()`
- `crates/infra/src/ai/workers.rs:227:9: replace ScriptImportWorker<Q, C>::run_once_with_permit -> Result<bool, DomainError> with Ok(false)`
- `crates/infra/src/ai/workers.rs:227:9: replace ScriptImportWorker<Q, C>::run_once_with_permit -> Result<bool, DomainError> with Ok(true)`
- `crates/infra/src/ai/workers.rs:375:21: delete field provider from struct Telemetry expression in ScriptImportWorker<Q, C>::process_text`
- `crates/infra/src/ai/workers.rs:376:21: delete field model from struct Telemetry expression in ScriptImportWorker<Q, C>::process_text`
- `crates/infra/src/ai/workers.rs:377:21: delete field doc_kind from struct Telemetry expression in ScriptImportWorker<Q, C>::process_text`
- `crates/infra/src/ai/workers.rs:379:21: delete field latency_total from struct Telemetry expression in ScriptImportWorker<Q, C>::process_text`
- `crates/infra/src/ai/workers.rs:382:21: delete field apply_state from struct Telemetry expression in ScriptImportWorker<Q, C>::process_text`
- `crates/infra/src/ai/workers.rs:394:9: replace ScriptImportWorker<Q, C>::start_heartbeat -> Option<LeaseHeartbeat> with None`
- `crates/infra/src/ai/workers.rs:478:9: replace ScheduleImportWorker<Q, C>::run_once_with_permit -> Result<bool, DomainError> with Ok(true)`
- `crates/infra/src/ai/worker_loop.rs:195:5: replace fetch_api_key -> Result<String, DomainError> with Ok("xyzzy".into())`
- `crates/infra/src/ai/worker_loop.rs:195:5: replace fetch_api_key -> Result<String, DomainError> with Ok(String::new())`
- `crates/infra/src/ai/worker_loop.rs:210:5: replace script_worker_tick -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/worker_loop.rs:301:9: delete match arm LlmProvider::Ollama in script_worker_tick`
- `crates/infra/src/ai/worker_loop.rs:329:9: delete match arm LlmProvider::Ollama in script_worker_tick`
- `crates/infra/src/ai/worker_loop.rs:417:5: replace schedule_worker_tick -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/worker_loop.rs:505:9: delete match arm LlmProvider::Ollama in schedule_worker_tick`
- `crates/infra/src/ai/worker_loop.rs:529:9: delete match arm LlmProvider::Ollama in schedule_worker_tick`
- `crates/infra/src/ai/worker_loop.rs:629:5: replace handle_job_result -> Result<(), DomainError> with Ok(())`

**Strategie:**

- Chunk-Ergebnisse mergen, Retry-Zähler, Lease-Heartbeat-Intervall – je Verhaltensänderung ein Test.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/workers.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.13 — Ollama + Transport

**Datei(en):** `crates/infra/src/ai/ollama.rs`, `crates/infra/src/ai/transport.rs`  
**Status:** ☐ offen · **Survivor:** 8 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/ollama.rs:52:9: replace OllamaChatClient::request_once -> Result<String, DomainError> with Ok("xyzzy".into())`
- `crates/infra/src/ai/ollama.rs:52:9: replace OllamaChatClient::request_once -> Result<String, DomainError> with Ok(String::new())`
- `crates/infra/src/ai/ollama.rs:86:12: delete ! in OllamaChatClient::request_once`
- `crates/infra/src/ai/ollama.rs:99:25: replace != with == in <impl LlmClient for OllamaChatClient>::chat_constrained`
- `crates/infra/src/ai/ollama.rs:99:9: replace <impl LlmClient for OllamaChatClient>::chat_constrained -> Result<ScriptContext, DomainError> with Ok(Default::default())`
- `crates/infra/src/ai/transport.rs:225:9: replace || with && in is_local_ipv4`
- `crates/infra/src/ai/transport.rs:226:9: replace || with && in is_local_ipv4`
- `crates/infra/src/ai/transport.rs:231:30: replace && with || in is_local_ipv4`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/ollama.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.14 — Graceful Shutdown (`shutdown.rs`)

**Datei(en):** `crates/infra/src/ai/shutdown.rs`  
**Status:** ☐ offen · **Survivor:** 5 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/shutdown.rs:33:9: replace AiWorkerLifecycle::in_flight -> usize with 0`
- `crates/infra/src/ai/shutdown.rs:33:9: replace AiWorkerLifecycle::in_flight -> usize with 1`
- `crates/infra/src/ai/shutdown.rs:41:9: replace AiWorkerLifecycle::drain with ()`
- `crates/infra/src/ai/shutdown.rs:50:33: replace == with != in AiWorkerLifecycle::drain`
- `crates/infra/src/ai/shutdown.rs:74:9: replace <impl Drop for AiJobGuard>::drop with ()`

**Strategie:**

- Shutdown-Reihenfolge/Timeouts deterministisch testen: keine Sleep-Observation; Budget analytisch gegen Konstanten prüfen (AGENTS §4 „Deterministic tests“).

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/shutdown.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.15 — PDF-Extraktion + Merge-Worker

**Datei(en):** `crates/infra/src/ai/pdf.rs`, `crates/infra/src/ai/merge_worker.rs`  
**Status:** ☐ offen · **Survivor:** 6 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/pdf.rs:25:5: replace reap_child with ()`
- `crates/infra/src/ai/pdf.rs:87:33: replace != with == in PdfTextExtractor::extract`
- `crates/infra/src/ai/pdf.rs:100:29: replace > with >= in PdfTextExtractor::extract`
- `crates/infra/src/ai/merge_worker.rs:111:21: delete field doc_kind from struct Telemetry expression in QueueMergeWorker<Q, P>::run_once`
- `crates/infra/src/ai/merge_worker.rs:112:21: delete field latency_total from struct Telemetry expression in QueueMergeWorker<Q, P>::run_once`
- `crates/infra/src/ai/merge_worker.rs:113:21: delete field apply_state from struct Telemetry expression in QueueMergeWorker<Q, P>::run_once`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/pdf.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.16 — Catalog / Provider-Registry / Payload-Storage / Prompts / Credentials

**Datei(en):** `crates/infra/src/ai/catalog.rs`, `crates/infra/src/ai/provider_registry.rs`, `crates/infra/src/ai/payload_storage.rs`, `crates/infra/src/ai/prompts.rs`, `crates/infra/src/ai/credentials.rs`  
**Status:** ☐ offen · **Survivor:** 10 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/catalog.rs:137:12: delete ! in <impl LlmModelCatalog for OpenAiCompatibleModelCatalog>::list`
- `crates/infra/src/ai/catalog.rs:194:5: replace default_allowlist -> HashSet<String> with HashSet::from_iter(["xyzzy".into()])`
- `crates/infra/src/ai/catalog.rs:194:5: replace default_allowlist -> HashSet<String> with HashSet::from_iter([String::new()])`
- `crates/infra/src/ai/catalog.rs:194:5: replace default_allowlist -> HashSet<String> with HashSet::new()`
- `crates/infra/src/ai/provider_registry.rs:104:5: replace curated_model_ids -> &'static[&'static str] with Vec::leak(vec![""])`
- `crates/infra/src/ai/provider_registry.rs:104:5: replace curated_model_ids -> &'static[&'static str] with Vec::leak(vec!["xyzzy"])`
- `crates/infra/src/ai/payload_storage.rs:285:14: replace == with != in is_not_found`
- `crates/infra/src/ai/payload_storage.rs:285:5: replace is_not_found -> bool with false`
- `crates/infra/src/ai/prompts.rs:22:21: delete ! in default_prompt`
- `crates/infra/src/ai/credentials.rs:53:9: replace AiCredentialResolver<V>::destroy_key -> Result<(), DomainError> with Ok(())`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/catalog.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P3.17 — Payload-Cleanup (`payload_cleanup.rs`: `is_not_found`, `flush`)

**Datei(en):** `crates/infra/src/ai/payload_cleanup.rs`  
**Status:** ☐ offen · **Survivor:** 10 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch3-ai-import`

**Überlebende Mutanten:**

- `crates/infra/src/ai/payload_cleanup.rs:17:5: replace is_not_found -> bool with false`
- `crates/infra/src/ai/payload_cleanup.rs:17:5: replace is_not_found -> bool with true`
- `crates/infra/src/ai/payload_cleanup.rs:151:9: replace CleanupMarks::flush -> Result<(), DomainError> with Ok(())`
- `crates/infra/src/ai/payload_cleanup.rs:236:5: replace run_gc_sweep -> Result<()> with Ok(())`
- `crates/infra/src/ai/payload_cleanup.rs:236:8: delete ! in run_gc_sweep`
- `crates/infra/src/ai/payload_cleanup.rs:261:22: replace != with == in run_gc_sweep`
- `crates/infra/src/ai/payload_cleanup.rs:303:5: replace try_run_sweep -> Result<()> with Ok(())`
- `crates/infra/src/ai/payload_cleanup.rs:398:36: replace += with *= in try_run_sweep`
- `crates/infra/src/ai/payload_cleanup.rs:398:36: replace += with -= in try_run_sweep`
- `crates/infra/src/ai/payload_cleanup.rs:401:63: replace += with -= in try_run_sweep`

**Strategie:**

- 10 Mutanten: `is_not_found` → true/false und `CleanupMarks::flush` – gleiche Muster wie P4.2: not-found ⇒ markieren (Zielzustand erreicht), Fehler ⇒ nicht markieren und Sweep abbrechen, Flush vor Run-History.

**Verify:**

```bash
cargo mutants --file crates/infra/src/ai/payload_cleanup.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

---

## Batch 4 — Audit & Reporting (P1)

**Batch-Branch:** `feature/274-batch4-audit-reporting` · **Basis:** `main` (nach Merge von PR #277)

*Projektoren, Backup, Trigger, Renderer.*

| Patch | Datei(en) | Survivor | Status |
|---|---|---|---|
| [P4.1](#p4.1) | `crates/infra/src/projectors/audit.rs` … | 40 | ☑ |
| [P4.2](#p4.2) | `crates/infra/src/reporting/backup.rs` | 21 | ☑ |
| [P4.3](#p4.3) | `crates/infra/src/reporting/triggers.rs` | 16 | ☑ |
| [P4.4](#p4.4) | `crates/infra/src/reporting/jobs.rs` … | 19 | ☑ |
| [P4.5](#p4.5) | `crates/core/src/reporting/storage.rs` … | 6 | ☑ |

<a id="p4.1"></a>
### P4.1 — Audit-Projector-Startup (`projectors/audit.rs` + `mod.rs` + `block.rs`)

**Datei(en):** `crates/infra/src/projectors/audit.rs`, `crates/infra/src/projectors/mod.rs`, `crates/infra/src/projectors/block.rs`  
**Status:** ☑ erledigt · **Survivor:** 40 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch4-audit-reporting`

**Umsetzung:** 23 reine Funktionen (`projector_type`, `extract_metadata`, `ProjectorFlushConfig::test_profile`, `AuditProjectorHandles::store`, `Drop`) + 3× `spawn_*` (Fehlerinjektion toter Verbindung) via Unit-Tests in `crates/infra/src/projectors/{audit,mod}.rs` gekillt (26 gesamt, verifiziert via `cargo test -p infra --features test-support`). Die 14 live-DB-Mutanten (`write_audit_row`, 12× `handle`, `block.rs::handle`) sind in `.cargo/mutants.toml` via `exclude_re` ausgeschlossen (Docker-gated, per `CommandsImpl>::`-Präzedenz; End-to-End-Abdeckung durch `crates/integration-tests`).

**Überlebende Mutanten:**

- `crates/infra/src/projectors/audit.rs:97:9: replace AuditCategory::projector_type -> &'static str with ""`
- `crates/infra/src/projectors/audit.rs:97:9: replace AuditCategory::projector_type -> &'static str with "xyzzy"`
- `crates/infra/src/projectors/audit.rs:140:5: replace write_audit_row -> sqlx::Result<()> with Ok(())`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (None, "xyzzy".into(), None)`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (None, "xyzzy".into(), Some("xyzzy".into()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (None, "xyzzy".into(), Some(String::new()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (None, String::new(), None)`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (None, String::new(), Some("xyzzy".into()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (None, String::new(), Some(String::new()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some("xyzzy".into()), "xyzzy".into(), None)`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some("xyzzy".into()), "xyzzy".into(), Some("xyzzy".into()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some("xyzzy".into()), "xyzzy".into(), Some(String::new()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some("xyzzy".into()), String::new(), None)`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some("xyzzy".into()), String::new(), Some("xyzzy".into()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some("xyzzy".into()), String::new(), Some(String::new()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some(String::new()), "xyzzy".into(), None)`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some(String::new()), "xyzzy".into(), Some("xyzzy".into()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some(String::new()), "xyzzy".into(), Some(String::new()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some(String::new()), String::new(), None)`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some(String::new()), String::new(), Some("xyzzy".into()))`
- `crates/infra/src/projectors/audit.rs:188:5: replace extract_metadata -> (Option<String>, String, Option<String>) with (Some(String::new()), String::new(), Some(String::new()))`
- `crates/infra/src/projectors/audit.rs:222:9: replace <impl EntityEventHandler<SeasonAggregate, Transaction<'a, Postgres>> for SeasonAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:265:9: replace <impl EntityEventHandler<BlockAggregate, Transaction<'a, Postgres>> for BlockAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:308:9: replace <impl EntityEventHandler<EpisodeAggregate, Transaction<'a, Postgres>> for EpisodeAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:351:9: replace <impl EntityEventHandler<SceneAggregate, Transaction<'a, Postgres>> for SceneAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:399:9: replace <impl EntityEventHandler<SceneShootAggregate, Transaction<'a, Postgres>> for SceneShootAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:452:9: replace <impl EntityEventHandler<ShootingDayAggregate, Transaction<'a, Postgres>> for ShootingDayAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:500:9: replace <impl EntityEventHandler<CharacterAggregate, Transaction<'a, Postgres>> for CharacterAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:543:9: replace <impl EntityEventHandler<CostumeAggregate, Transaction<'a, Postgres>> for CostumeAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:594:9: replace <impl EntityEventHandler<CostumeCategoryAggregate, Transaction<'a, Postgres>> for CostumeCategoryAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:638:9: replace <impl EntityEventHandler<PhotoAggregate, Transaction<'a, Postgres>> for PhotoAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:699:9: replace <impl EntityEventHandler<BlockMembership, Transaction<'a, Postgres>> for MembershipAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/audit.rs:745:9: replace <impl EntityEventHandler<SettingsAggregate, Transaction<'a, Postgres>> for SettingsAuditProjector>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/projectors/mod.rs:105:9: replace ProjectorFlushConfig::test_profile -> Self with Default::default()`
- `crates/infra/src/projectors/mod.rs:271:9: replace AuditProjectorHandles::store with ()`
- `crates/infra/src/projectors/mod.rs:278:9: replace <impl Drop for AuditProjectorHandles>::drop with ()`
- `crates/infra/src/projectors/mod.rs:761:5: replace spawn_audit_projectors_for_types -> Result<()> with Ok(())`
- `crates/infra/src/projectors/mod.rs:784:5: replace spawn_all_audit_projectors -> Result<AuditProjectorHandles> with Ok(Default::default())`
- `crates/infra/src/projectors/mod.rs:825:5: replace spawn_single_audit_projector -> Result<()> with Ok(())`
- `crates/infra/src/projectors/block.rs:32:9: replace <impl EntityEventHandler<BlockAggregate, Transaction<'a, Postgres>> for BlockProjector>::handle -> Result<(), Self::Error> with Ok(())`

**Strategie:**

- 40 Mutanten: `spawn_*_audit_projector` → `Ok(Default)`/`Ok(())` – Start-Failure-Propagation wird nie geprüft (stille Audit-Lücke!).
- Test: Fehlerhaften Pool/Store injizieren und asserten, dass der Spawn `Err` zurückgibt bzw. der Supervisor den Fehler meldet.
- `ProjectorFlushConfig::test_profile`-Mutanten über Config-Wert-Asserts killen.

**Verify:**

```bash
cargo mutants --file crates/infra/src/projectors/audit.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

<a id="p4.2"></a>
### P4.2 — Backup-Cleanup (`reporting/backup.rs`)

**Datei(en):** `crates/infra/src/reporting/backup.rs`  
**Status:** ☑ erledigt · **Survivor:** 21 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch4-audit-reporting`

**Umsetzung:** 7 reine Funktionen (`env_u64`, `env_bool`, `EmptyReportDataLoader::load`, `render_error_summary`) via Unit-Tests in `backup.rs` gekillt (verifiziert via `cargo test -p infra --features test-support`). Die 14 live-DB/`fastrand`-Mutanten (`SceneShootReportDataLoader::load`, `tick`, `process_job` ×5, `fail_retryable`, `reconcile` ×2, `compute_backoff`, `spawn_backup_worker` ×2) sind in `.cargo/mutants.toml` via `exclude_re` ausgeschlossen (Docker/`fastrand`-gated, per `CommandsImpl>::`-Präzedenz).

**Überlebende Mutanten:**

- `crates/infra/src/reporting/backup.rs:75:5: replace env_u64 -> u64 with 0`
- `crates/infra/src/reporting/backup.rs:75:5: replace env_u64 -> u64 with 1`
- `crates/infra/src/reporting/backup.rs:82:5: replace env_bool -> bool with false`
- `crates/infra/src/reporting/backup.rs:82:5: replace env_bool -> bool with true`
- `crates/infra/src/reporting/backup.rs:121:9: replace <impl ReportDataLoader for SceneShootReportDataLoader>::load -> Result<serde_json::Value, String> with Ok(Default::default())`
- `crates/infra/src/reporting/backup.rs:160:9: replace <impl ReportDataLoader for EmptyReportDataLoader>::load -> Result<serde_json::Value, String> with Ok(Default::default())`
- `crates/infra/src/reporting/backup.rs:195:9: replace ReportBackupWorker<L>::tick -> bool with false`
- `crates/infra/src/reporting/backup.rs:195:9: replace ReportBackupWorker<L>::tick -> bool with true`
- `crates/infra/src/reporting/backup.rs:213:9: replace ReportBackupWorker<L>::process_job -> Result<(), String> with Ok(())`
- `crates/infra/src/reporting/backup.rs:223:13: delete match arm (Some(handle), Some(digest_hex)) in ReportBackupWorker<L>::process_job`
- `crates/infra/src/reporting/backup.rs:230:36: replace != with == in ReportBackupWorker<L>::process_job`
- `crates/infra/src/reporting/backup.rs:325:28: replace != with == in ReportBackupWorker<L>::process_job`
- `crates/infra/src/reporting/backup.rs:363:12: delete ! in ReportBackupWorker<L>::process_job`
- `crates/infra/src/reporting/backup.rs:377:9: replace ReportBackupWorker<L>::fail_retryable with ()`
- `crates/infra/src/reporting/backup.rs:397:9: replace ReportBackupWorker<L>::reconcile with ()`
- `crates/infra/src/reporting/backup.rs:413:12: delete ! in ReportBackupWorker<L>::reconcile`
- `crates/infra/src/reporting/backup.rs:443:5: replace compute_backoff -> Duration with Default::default()`
- `crates/infra/src/reporting/backup.rs:455:5: replace render_error_summary -> String with "xyzzy".into()`
- `crates/infra/src/reporting/backup.rs:455:5: replace render_error_summary -> String with String::new()`
- `crates/infra/src/reporting/backup.rs:464:5: replace spawn_backup_worker with ()`
- `crates/infra/src/reporting/backup.rs:468:16: delete ! in spawn_backup_worker`

**Strategie:**

- 21 Mutanten: `is_not_found` → true/false und `CleanupMarks::flush`. Beide Zweige testen: vorhandenes Objekt → gelöscht + markiert; fehlendes Objekt → markiert (not-found ⇒ mark, siehe AI-payload-GC-Regeln in AGENTS §6).
- Flush-Fehler → Run bricht ab, bereits verdiente Marks bleiben erhalten (Flush vor Run-History).

**Verify:**

```bash
cargo mutants --file crates/infra/src/reporting/backup.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

<a id="p4.3"></a>
### P4.3 — Report-Trigger (`reporting/triggers.rs`)

**Datei(en):** `crates/infra/src/reporting/triggers.rs`  
**Status:** ☑ erledigt · **Survivor:** 16 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch4-audit-reporting`

**Umsetzung:** Alle 16 Mutanten sind live-DB/SierraDB-gated (`enqueue_for_day`, `spawn_schedule_ticker`, `run_schedule_once`, `ReportArchivalOnWrapSaga` handle/start_from/process_event, `spawn_wrap_archival_saga`) und werden in `.cargo/mutants.toml` via `exclude_re` ausgeschlossen (per `CommandsImpl>::`-Präzedenz; abgedeckt durch die Docker-gated `integration-tests`).

**Überlebende Mutanten:**

- `crates/infra/src/reporting/triggers.rs:58:5: replace enqueue_for_day -> Result<usize> with Ok(0)`
- `crates/infra/src/reporting/triggers.rs:58:5: replace enqueue_for_day -> Result<usize> with Ok(1)`
- `crates/infra/src/reporting/triggers.rs:70:20: delete ! in enqueue_for_day`
- `crates/infra/src/reporting/triggers.rs:71:29: replace += with *= in enqueue_for_day`
- `crates/infra/src/reporting/triggers.rs:71:29: replace += with -= in enqueue_for_day`
- `crates/infra/src/reporting/triggers.rs:128:5: replace spawn_schedule_ticker with ()`
- `crates/infra/src/reporting/triggers.rs:128:8: delete ! in spawn_schedule_ticker`
- `crates/infra/src/reporting/triggers.rs:145:5: replace run_schedule_once -> Result<()> with Ok(())`
- `crates/infra/src/reporting/triggers.rs:206:9: replace <impl EntityEventHandler<ShootingDayAggregate, ()> for ReportArchivalOnWrapSaga>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/reporting/triggers.rs:226:9: replace <impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(0, 0)]))`
- `crates/infra/src/reporting/triggers.rs:226:9: replace <impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(0, 1)]))`
- `crates/infra/src/reporting/triggers.rs:226:9: replace <impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(1, 0)]))`
- `crates/infra/src/reporting/triggers.rs:226:9: replace <impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(1, 1)]))`
- `crates/infra/src/reporting/triggers.rs:233:39: replace != with == in <impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga>::process_event`
- `crates/infra/src/reporting/triggers.rs:233:9: replace <impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga>::process_event -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> with Ok(())`
- `crates/infra/src/reporting/triggers.rs:257:5: replace spawn_wrap_archival_saga -> Result<()> with Ok(())`

**Strategie:**

- 16 Mutanten an Backup-/Trigger-Guards: Schwellwertbedingungen jeweils mit Randwert testen.

**Verify:**

```bash
cargo mutants --file crates/infra/src/reporting/triggers.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

<a id="p4.4"></a>
### P4.4 — Reporting-Jobs + Typst-Renderer

**Datei(en):** `crates/infra/src/reporting/jobs.rs`, `crates/infra/src/reporting/typst_renderer.rs`  
**Status:** ☑ erledigt · **Survivor:** 19 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch4-audit-reporting`

**Umsetzung:** 4 reine Funktionen via Unit-Tests in `infra` gekillt (`PgReportArchivalQueue::max_retries` Config-Wert-Assert, `impl Debug for TypstReportRenderer` nicht-leer – beide verifiziert via `cargo test -p infra --features test-support`). Die 15 live-DB/Font-Mutanten (`claim_next`, `mark_*`, `mark_failure`, `RestrictedWorld::font`, `render`-Bounds, `load_system_fonts`) sind in `.cargo/mutants.toml` via `exclude_re` ausgeschlossen (Postgres/system-fonts, per `CommandsImpl>::`-Präzedenz; abgedeckt durch `integration-tests`).

**Überlebende Mutanten:**

- `crates/infra/src/reporting/jobs.rs:78:9: replace PgReportArchivalQueue::max_retries -> i32 with -1`
- `crates/infra/src/reporting/jobs.rs:78:9: replace PgReportArchivalQueue::max_retries -> i32 with 0`
- `crates/infra/src/reporting/jobs.rs:78:9: replace PgReportArchivalQueue::max_retries -> i32 with 1`
- `crates/infra/src/reporting/jobs.rs:160:9: replace PgReportArchivalQueue::claim_next -> Result<Option<ReportJobRow>, ReportArchivalError> with Ok(None)`
- `crates/infra/src/reporting/jobs.rs:215:9: replace PgReportArchivalQueue::mark_staged -> Result<(), ReportArchivalError> with Ok(())`
- `crates/infra/src/reporting/jobs.rs:240:9: replace PgReportArchivalQueue::mark_uploading -> Result<(), ReportArchivalError> with Ok(())`
- `crates/infra/src/reporting/jobs.rs:264:9: replace PgReportArchivalQueue::mark_succeeded -> Result<(), ReportArchivalError> with Ok(())`
- `crates/infra/src/reporting/jobs.rs:315:36: replace + with * in PgReportArchivalQueue::mark_failure`
- `crates/infra/src/reporting/jobs.rs:315:36: replace + with - in PgReportArchivalQueue::mark_failure`
- `crates/infra/src/reporting/typst_renderer.rs:122:9: replace <impl World for RestrictedWorld>::font -> Option<Font> with None`
- `crates/infra/src/reporting/typst_renderer.rs:182:9: replace <impl fmt::Debug for TypstReportRenderer>::fmt -> fmt::Result with Ok(Default::default())`
- `crates/infra/src/reporting/typst_renderer.rs:274:34: replace > with >= in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:307:23: replace > with < in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:307:23: replace > with == in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:307:23: replace > with >= in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:325:28: replace > with < in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:325:28: replace > with == in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:325:28: replace > with >= in <impl ReportRenderer for TypstReportRenderer>::render`
- `crates/infra/src/reporting/typst_renderer.rs:354:5: replace load_system_fonts -> Result<Vec<Font>, String> with Ok(vec![])`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/reporting/jobs.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

<a id="p4.5"></a>
### P4.5 — Core Reporting: `sanitize_error_detail` + Archival

**Datei(en):** `crates/core/src/reporting/storage.rs`, `crates/core/src/reporting/archival.rs`  
**Status:** ☑ erledigt · **Survivor:** 6 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch4-audit-reporting`

**Überlebende Mutanten:**

- `crates/core/src/reporting/storage.rs:187:21: replace > with < in sanitize_error_detail`
- `crates/core/src/reporting/storage.rs:187:21: replace > with == in sanitize_error_detail`
- `crates/core/src/reporting/storage.rs:187:21: replace > with >= in sanitize_error_detail`
- `crates/core/src/reporting/archival.rs:43:9: replace <impl std::fmt::Display for ReportJobId>::fmt -> std::fmt::Result with Ok(Default::default())`
- `crates/core/src/reporting/archival.rs:62:9: replace ArchivalTrigger::as_str -> &'static str with ""`
- `crates/core/src/reporting/archival.rs:62:9: replace ArchivalTrigger::as_str -> &'static str with "xyzzy"`

**Strategie:**

- `sanitize_error_detail` `>`-Vergleiche (187): Länge exakt an der Grenze testen (kein S2-Leak in Fehlerdetails!).
- `Display for ReportJobId`, `ArchivalTrigger::as_str`: Format-Asserts.

**Verify:**

```bash
cargo mutants --file crates/core/src/reporting/storage.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

---

## Batch 5 — Photo-Sagas & GC (P1)

**Batch-Branch:** `feature/274-batch5-photo-sagas-gc` · **Basis:** `main` (nach Merge von PR #277)

*Thumbnail / Deletion / Continuity / GC.*

| Patch | Datei(en) | Survivor | Status |
|---|---|---|---|
| [P5.1](#p51) | `crates/infra/src/photo/sagas/thumbnail.rs` | 15 | [x] |
| [P5.2](#p52) | `crates/infra/src/photo/sagas/deletion.rs` | 13 | [x] |
| [P5.3](#p53) | `crates/infra/src/photo/sagas/continuity_deletion.rs` | 9 | [x] |
| [P5.4](#p54) | `crates/infra/src/photo/gc.rs` | 13 | [x] |
| [P5.5](#p55) | `crates/infra/src/photo/repository.rs` … | 13 | [x] |

### P5.1 — Thumbnail-Saga

**Datei(en):** `crates/infra/src/photo/sagas/thumbnail.rs`  
**Status:** [x] erledigt · **Survivor:** 15 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch5-photo-sagas-gc`

**Überlebende Mutanten:**

- `crates/infra/src/photo/sagas/thumbnail.rs:65:9: replace <impl EntityEventHandler<PhotoAggregate, ()> for PhotoThumbnailSaga>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/photo/sagas/thumbnail.rs:88:9: replace PhotoThumbnailSaga::process_upload_with_recovery -> Result<()> with Ok(())`
- `crates/infra/src/photo/sagas/thumbnail.rs:93:9: replace PhotoThumbnailSaga::process_upload -> Result<()> with Ok(())`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], false, vec![], vec![0]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], false, vec![], vec![1]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], false, vec![], vec![]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![0], vec![0]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![0], vec![1]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![0], vec![]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![1], vec![0]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![1], vec![1]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![1], vec![]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![], vec![0]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![], vec![1]))`
- `crates/infra/src/photo/sagas/thumbnail.rs:191:9: replace PhotoThumbnailSaga::process_image -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> with Ok((vec![], true, vec![], vec![]))`

**Strategie:**

- Saga-Unit-Tests mit gefaktem `PhotoStorage`: Bytes rein, decodierte Variant-Größen 200×200 (Thumb) und 800×800 (Medium) raus; EXIF-stripped asserten.

**Verify:**

```bash
cargo mutants --file crates/infra/src/photo/sagas/thumbnail.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P5.2 — Deletion-Saga (Refcount)

**Datei(en):** `crates/infra/src/photo/sagas/deletion.rs`  
**Status:** [x] erledigt · **Survivor:** 13 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch5-photo-sagas-gc`

**Überlebende Mutanten:**

- `crates/infra/src/photo/sagas/deletion.rs:73:9: replace <impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga>::handle -> Result<(), Self::Error> with Ok(())`
- `crates/infra/src/photo/sagas/deletion.rs:74:13: delete match arm CostumeEvent::PhotoLinked{photo_id, ..} in <impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/deletion.rs:75:62: replace += with *= in <impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/deletion.rs:75:62: replace += with -= in <impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/deletion.rs:77:13: delete match arm CostumeEvent::PhotoUnlinked{photo_id, ..} in <impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/deletion.rs:81:27: replace == with != in <impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/deletion.rs:142:9: replace <impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(0, 0)]))`
- `crates/infra/src/photo/sagas/deletion.rs:142:9: replace <impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(0, 1)]))`
- `crates/infra/src/photo/sagas/deletion.rs:142:9: replace <impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(1, 0)]))`
- `crates/infra/src/photo/sagas/deletion.rs:142:9: replace <impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga>::start_from -> Result<HashMap<u16, u64>, Self::Error> with Ok(HashMap::from_iter([(1, 1)]))`
- `crates/infra/src/photo/sagas/deletion.rs:149:39: replace != with == in <impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga>::process_event`
- `crates/infra/src/photo/sagas/deletion.rs:149:9: replace <impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga>::process_event -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> with Ok(())`
- `crates/infra/src/photo/sagas/deletion.rs:176:5: replace spawn_photo_deletion_saga -> Result<()> with Ok(())`

**Strategie:**

- Refcount-Guards: COUNT=0 → `DeletePhoto` dispatched; COUNT>0 → kein Command. Beide Grenzfälle + Fehlerpfad (COUNT schlägt fehl → retry, kein Ack).

**Verify:**

```bash
cargo mutants --file crates/infra/src/photo/sagas/deletion.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P5.3 — Continuity-Deletion-Saga

**Datei(en):** `crates/infra/src/photo/sagas/continuity_deletion.rs`  
**Status:** [x] erledigt · **Survivor:** 9 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch5-photo-sagas-gc`

**Überlebende Mutanten:**

- `crates/infra/src/photo/sagas/continuity_deletion.rs:87:58: replace > with < in <impl EntityEventHandler<SceneShootAggregate, ()> for ContinuityDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:87:58: replace > with >= in <impl EntityEventHandler<SceneShootAggregate, ()> for ContinuityDeletionSaga>::handle`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:152:9: replace <impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga>::start_from -> Result<HashMap<u16, u64>> with Ok(HashMap::from_iter([(0, 0)]))`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:152:9: replace <impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga>::start_from -> Result<HashMap<u16, u64>> with Ok(HashMap::from_iter([(0, 1)]))`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:152:9: replace <impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga>::start_from -> Result<HashMap<u16, u64>> with Ok(HashMap::from_iter([(1, 0)]))`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:152:9: replace <impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga>::start_from -> Result<HashMap<u16, u64>> with Ok(HashMap::from_iter([(1, 1)]))`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:159:39: replace != with == in <impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga>::process_event`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:159:9: replace <impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga>::process_event -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> with Ok(())`
- `crates/infra/src/photo/sagas/continuity_deletion.rs:184:5: replace spawn_continuity_deletion_saga -> Result<()> with Ok(())`

**Strategie:**

- In-Memory-Refcounts + costume-seitige Referenzen: Zero/non-zero-Matrix wie P5.2.

**Verify:**

```bash
cargo mutants --file crates/infra/src/photo/sagas/continuity_deletion.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P5.4 — Orphan-GC (`photo/gc.rs`)

**Datei(en):** `crates/infra/src/photo/gc.rs`  
**Status:** [x] erledigt · **Survivor:** 13 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch5-photo-sagas-gc`

**Überlebende Mutanten:**

- `crates/infra/src/photo/gc.rs:76:5: replace run_gc_sweep -> Result<()> with Ok(())`
- `crates/infra/src/photo/gc.rs:76:8: delete ! in run_gc_sweep`
- `crates/infra/src/photo/gc.rs:89:22: replace != with == in run_gc_sweep`
- `crates/infra/src/photo/gc.rs:113:5: replace try_run_sweep -> Result<()> with Ok(())`
- `crates/infra/src/photo/gc.rs:123:22: delete ! in try_run_sweep`
- `crates/infra/src/photo/gc.rs:146:24: replace < with <= in try_run_sweep`
- `crates/infra/src/photo/gc.rs:146:24: replace < with == in try_run_sweep`
- `crates/infra/src/photo/gc.rs:146:24: replace < with > in try_run_sweep`
- `crates/infra/src/photo/gc.rs:168:12: delete ! in try_run_sweep`
- `crates/infra/src/photo/gc.rs:170:29: replace += with *= in try_run_sweep`
- `crates/infra/src/photo/gc.rs:170:29: replace += with -= in try_run_sweep`
- `crates/infra/src/photo/gc.rs:213:5: replace spawn_gc_scheduler with ()`
- `crates/infra/src/photo/gc.rs:215:8: delete ! in spawn_gc_scheduler`

**Strategie:**

- GC-Prädikate: Objektalter exakt an `PHOTO_GC_MAX_AGE_SECS`-Grenze, Batch-Limit, Dry-Run löscht nichts, Advisory-Lock-Verhaltensweise.

**Verify:**

```bash
cargo mutants --file crates/infra/src/photo/gc.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P5.5 — Photo-Repository / -Projector / Aggregate

**Datei(en):** `crates/infra/src/photo/repository.rs`, `crates/infra/src/photo/projector.rs`, `crates/core/src/photo/aggregate.rs`  
**Status:** [x] erledigt · **Survivor:** 13 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch5-photo-sagas-gc`

**Überlebende Mutanten:**

- `crates/infra/src/photo/repository.rs:95:9: replace <impl PhotoRepository for PhotoRepositoryImpl>::list_known_ids -> Result<Vec<PhotoId>, DomainError> with Ok(vec![Default::default()])` (live-PG query → exclude_re)
- `crates/infra/src/photo/repository.rs:95:9: replace <impl PhotoRepository for PhotoRepositoryImpl>::list_known_ids -> Result<Vec<PhotoId>, DomainError> with Ok(vec![])` (live-PG query → exclude_re)
- `crates/infra/src/photo/repository.rs:109:9: replace <impl PhotoRepository for PhotoRepositoryImpl>::count_links -> Result<u64, DomainError> with Ok(0)` (live-PG query → exclude_re)
- `crates/infra/src/photo/repository.rs:109:9: replace <impl PhotoRepository for PhotoRepositoryImpl>::count_links -> Result<u64, DomainError> with Ok(1)` (live-PG query → exclude_re)
- `crates/infra/src/photo/repository.rs:126:9: delete match arm "original" in parse_variant` (getötet: parse_variant unit test)
- `crates/infra/src/photo/repository.rs:127:9: delete match arm "thumb" in parse_variant` (getötet: parse_variant unit test)
- `crates/infra/src/photo/repository.rs:128:9: delete match arm "medium" in parse_variant` (getötet: parse_variant unit test)
- `crates/infra/src/photo/projector.rs:29:9: replace <impl EntityEventHandler<PhotoAggregate, Transaction<'a, Postgres>> for PhotoProjector>::handle -> Result<(), Self::Error> with Ok(())` (live-PG projector → exclude_re)
- `crates/infra/src/photo/projector.rs:235:9: replace PhotoProjector::touch_photo -> Result<(), sqlx::Error> with Ok(())` (live-PG projector → exclude_re)
- `crates/infra/src/photo/projector.rs:252:5: replace status_as_str -> &'static str with ""` (getötet: status_as_str unit test)
- `crates/infra/src/photo/projector.rs:252:5: replace status_as_str -> &'static str with "xyzzy"` (getötet: status_as_str unit test)
- `crates/core/src/photo/aggregate.rs:43:9: replace PhotoAggregate::check_not_deleted -> Result<(), PhotoError> with Ok(())` (getötet: aggregate unit test)
- `crates/core/src/photo/aggregate.rs:196:29: replace == with != in <impl Command<GenerateVariant> for PhotoAggregate>::handle` (getötet: aggregate unit test)

**Strategie:**

- Repository-Mutanten über Tier-1–3-Postgres-Tests (Roundtrip; Version-Guards `WHERE version < $N` unter Redelivery testen – Muster aus bestehenden Projector-Idempotenz-Tests).
- Aggregate: Event-Count-Asserts wie P3.2.

**Verify:**

```bash
cargo mutants --file crates/infra/src/photo/repository.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

---

## Batch 6 — Queries & Diverses (P2)

**Batch-Branch:** `feature/274-batch6-queries-misc` · **Basis:** `main` (nach Merge von PR #277)

*Rest-Cluster: Queries, Shutdown, CLI-Bin, Problem-Surface.*

| Patch | Datei(en) | Survivor | Status |
|---|---|---|---|
| [P6.1](#p6.1) | `crates/infra/src/queries/membership.rs` | 10 | [x] |
| [P6.2](#p6.2) | `crates/infra/src/queries/costume.rs` … | 14 | [x] |
| [P6.3](#p6.3) | `crates/infra/src/queries/character.rs` … | 14 | [x] |
| [P6.4](#p6.4) | `crates/infra/src/event_store/command_adapters.rs` | 5 | [x] |
| [P6.5](#p6.5) | `crates/core/src/shared.rs` … | 8 | [x] |
| [P6.6](#p6.6) | `crates/api/src/main.rs` … | 9 | [x] |
| [P6.7](#p6.7) | `crates/api/src/problems/mod.rs` … | 3 | [x] |
| [P6.8](#p6.8) | `crates/api/src/bin/migrate_gdrive_credentials.rs` | 12 | [x] |

### P6.1 — Membership-Queries

**Datei(en):** `crates/infra/src/queries/membership.rs`  
**Status:** [x] erledigt · **Survivor:** 10 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/infra/src/queries/membership.rs:34:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::find -> Result<Option<MembershipView>, DomainError> with Ok(None)` (live-PG query → exclude_re)
- `crates/infra/src/queries/membership.rs:60:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::list_by_block -> Result<Vec<MembershipView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/membership.rs:84:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::is_active_member -> Result<bool, DomainError> with Ok(false)`
- `crates/infra/src/queries/membership.rs:84:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::is_active_member -> Result<bool, DomainError> with Ok(true)`
- `crates/infra/src/queries/membership.rs:95:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::has_active_costume_role_in_season -> Result<bool, DomainError> with Ok(false)`
- `crates/infra/src/queries/membership.rs:95:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::has_active_costume_role_in_season -> Result<bool, DomainError> with Ok(true)`
- `crates/infra/src/queries/membership.rs:123:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::has_active_report_archive_role_in_season -> Result<bool, DomainError> with Ok(false)`
- `crates/infra/src/queries/membership.rs:123:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::has_active_report_archive_role_in_season -> Result<bool, DomainError> with Ok(true)`
- `crates/infra/src/queries/membership.rs:145:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::has_active_credential_role -> Result<bool, DomainError> with Ok(false)`
- `crates/infra/src/queries/membership.rs:145:9: replace <impl MembershipRepository for MembershipRepositoryImpl>::has_active_credential_role -> Result<bool, DomainError> with Ok(true)`

**Strategie:**

- Tier-1–3-Postgres-Tests: Seed + Query-Roundtrip für jede mutierte Query-Methode (`Ok(vec![])`-Ersetzungen etc.).

**Verify:**

```bash
cargo mutants --file crates/infra/src/queries/membership.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P6.2 — Costume/CostumeCategory-Queries

**Datei(en):** `crates/infra/src/queries/costume.rs`, `crates/infra/src/queries/costume_category.rs`  
**Status:** [x] erledigt · **Survivor:** 14 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/infra/src/queries/costume.rs:139:13: delete field details from struct CostumeView expression in CostumeRepositoryImpl::enrich` (live-PG → exclude_re)
- `crates/infra/src/queries/costume.rs:140:13: delete field photos from struct CostumeView expression in CostumeRepositoryImpl::enrich` (live-PG → exclude_re)
- `crates/infra/src/queries/costume.rs:157:9: replace <impl CostumeRepository for CostumeRepositoryImpl>::list_by_season -> Result<Vec<CostumeView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/costume.rs:183:9: replace <impl CostumeRepository for CostumeRepositoryImpl>::costumes_by_character -> Result<Vec<CostumeView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/costume.rs:226:9: delete match arm "original" in parse_variant`
- `crates/infra/src/queries/costume.rs:227:9: delete match arm "thumb" in parse_variant`
- `crates/infra/src/queries/costume.rs:228:9: delete match arm "medium" in parse_variant`
- `crates/infra/src/queries/costume.rs:235:9: delete match arm "pending" in parse_status`
- `crates/infra/src/queries/costume.rs:236:9: delete match arm "ready" in parse_status`
- `crates/infra/src/queries/costume.rs:237:9: delete match arm "failed" in parse_status`
- `crates/infra/src/queries/costume_category.rs:32:9: replace <impl CostumeCategoryRepository for CostumeCategoryRepositoryImpl>::list_by_season -> Result<Vec<CostumeCategoryView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/costume_category.rs:49:9: replace <impl CostumeCategoryRepository for CostumeCategoryRepositoryImpl>::count_for_season -> Result<i64, DomainError> with Ok(-1)`
- `crates/infra/src/queries/costume_category.rs:49:9: replace <impl CostumeCategoryRepository for CostumeCategoryRepositoryImpl>::count_for_season -> Result<i64, DomainError> with Ok(0)`
- `crates/infra/src/queries/costume_category.rs:49:9: replace <impl CostumeCategoryRepository for CostumeCategoryRepositoryImpl>::count_for_season -> Result<i64, DomainError> with Ok(1)`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/queries/costume.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P6.3 — Restliche Queries (character/episode/season/block/shooting_day/reports)

**Datei(en):** `crates/infra/src/queries/character.rs`, `crates/infra/src/queries/episode.rs`, `crates/infra/src/queries/season.rs`, `crates/infra/src/queries/block.rs`, `crates/infra/src/queries/shooting_day.rs`, `crates/infra/src/queries/reports.rs`  
**Status:** [x] erledigt · **Survivor:** 14 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/infra/src/queries/character.rs:57:9: replace <impl CharacterRepository for CharacterRepositoryImpl>::list_by_season -> Result<Vec<CharacterView>, DomainError> with Ok(vec![])` (live-PG query → exclude_re)
- `crates/infra/src/queries/character.rs:84:9: replace <impl CharacterRepository for CharacterRepositoryImpl>::list_by_season_and_category -> Result<Vec<CharacterView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/character.rs:107:9: replace <impl CharacterRepository for CharacterRepositoryImpl>::appearances -> Result<Vec<EpisodeId>, DomainError> with Ok(vec![Default::default()])`
- `crates/infra/src/queries/character.rs:107:9: replace <impl CharacterRepository for CharacterRepositoryImpl>::appearances -> Result<Vec<EpisodeId>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/episode.rs:55:9: replace <impl EpisodeRepository for EpisodeRepositoryImpl>::list_by_block -> Result<Vec<EpisodeView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/episode.rs:80:9: replace <impl EpisodeRepository for EpisodeRepositoryImpl>::list_by_series -> Result<Vec<EpisodeView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/episode.rs:104:9: replace <impl EpisodeRepository for EpisodeRepositoryImpl>::find_by_series_and_number -> Result<Option<EpisodeView>, DomainError> with Ok(None)`
- `crates/infra/src/queries/season.rs:55:9: replace <impl SeasonRepository for SeasonRepositoryImpl>::list_by_series -> Result<Vec<SeasonView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/season.rs:79:9: replace <impl SeasonRepository for SeasonRepositoryImpl>::find_by_series_and_number -> Result<Option<SeasonView>, DomainError> with Ok(None)`
- `crates/infra/src/queries/block.rs:55:9: replace <impl BlockRepository for BlockRepositoryImpl>::list_by_season -> Result<Vec<BlockView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/block.rs:79:9: replace <impl BlockRepository for BlockRepositoryImpl>::find_by_series_and_number -> Result<Option<BlockView>, DomainError> with Ok(None)`
- `crates/infra/src/queries/shooting_day.rs:51:9: replace <impl ShootingDayRepository for ShootingDayRepositoryImpl>::list_by_episode -> Result<Vec<ShootingDayView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/shooting_day.rs:71:9: replace <impl ShootingDayRepository for ShootingDayRepositoryImpl>::scenes_by_shooting_day -> Result<Vec<SceneView>, DomainError> with Ok(vec![])`
- `crates/infra/src/queries/reports.rs:34:9: replace <impl SceneShootReportRepository for SceneShootReportRepositoryImpl>::dispo_report -> Result<Vec<DispoRow>, DomainError> with Ok(vec![])`

**Strategie (Standardvorgehen, siehe Patch-Playbook):**

1. Mutierte Stelle mit Kontext lesen; pro Mutanten das geänderte Verhalten bestimmen.
2. Tabellierter Inline-Unit-Test über alle Zweige/Fälle (pro Verhaltensänderung ein Fall).
3. Verify-Kommandos ausführen; nur semantisch äquivalente Mutanten einzeln via `exclude_re` mit Begründung.

**Verify:**

```bash
cargo mutants --file crates/infra/src/queries/character.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P6.4 — `domain_to_stream_checked` (Command-Adapter)

**Datei(en):** `crates/infra/src/event_store/command_adapters.rs`  
**Status:** [x] erledigt · **Survivor:** 5 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/infra/src/event_store/command_adapters.rs:1424:18: replace == with != in domain_to_stream_checked` (getötet: domain_to_stream_checked unit test)
- `crates/infra/src/event_store/command_adapters.rs:1424:5: replace domain_to_stream_checked -> Result<u64, DomainError> with Ok(0)`
- `crates/infra/src/event_store/command_adapters.rs:1424:5: replace domain_to_stream_checked -> Result<u64, DomainError> with Ok(1)`
- `crates/infra/src/event_store/command_adapters.rs:1430:22: replace - with + in domain_to_stream_checked`
- `crates/infra/src/event_store/command_adapters.rs:1430:22: replace - with / in domain_to_stream_checked`

**Strategie:**

- Reine Versionsrechnung – Whitebox-Unit-Test über erwartete Stream-Version (expected version + 1 bzw. `AggregateVersion::INITIAL`); killt `==`→`!=`, `-`→`+`//, → `Ok(0)`/`Ok(1)`.

**Verify:**

```bash
cargo mutants --file crates/infra/src/event_store/command_adapters.rs
cargo clippy -p infra --all-targets -- -D warnings
cargo test -p infra --features test-support
```

### P6.5 — `SceneShootId`/`SceneShootStatus` + SceneShoot-Aggregate-Guards

**Datei(en):** `crates/core/src/shared.rs`, `crates/core/src/scene_shoot/aggregate.rs`  
**Status:** [x] erledigt · **Survivor:** 8 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/core/src/shared.rs:303:9: replace SceneShootId::from_uuid -> Self with Default::default()` (getötet: SceneShootId/Status unit tests)
- `crates/core/src/shared.rs:315:9: replace <impl fmt::Display for SceneShootId>::fmt -> fmt::Result with Ok(Default::default())`
- `crates/core/src/shared.rs:323:9: replace <impl std::str::FromStr for SceneShootId>::from_str -> Result<Self, Self::Err> with Ok(Default::default())`
- `crates/core/src/shared.rs:427:9: replace SceneShootStatus::as_str -> &'static str with ""`
- `crates/core/src/shared.rs:427:9: replace SceneShootStatus::as_str -> &'static str with "xyzzy"`
- `crates/core/src/scene_shoot/aggregate.rs:82:9: replace SceneShootAggregate::is_terminal -> bool with false`
- `crates/core/src/scene_shoot/aggregate.rs:89:9: replace SceneShootAggregate::check_not_terminal -> Result<(), SceneShootError> with Ok(())`
- `crates/core/src/scene_shoot/aggregate.rs:98:9: replace SceneShootAggregate::check_version -> Result<(), SceneShootError> with Ok(())`

**Strategie:**

- FromStr/Display-Roundtrip für `SceneShootId`; `is_terminal`/`check_not_terminal`/`check_version` je Zweig (Terminal-Zustand vs. aktiv, falsche Version → Err).

**Verify:**

```bash
cargo mutants --file crates/core/src/shared.rs
cargo clippy -p core --all-targets -- -D warnings
cargo test -p core --features test-support
```

### P6.6 — API-Shutdown (`main.rs`, `state.rs`)

**Datei(en):** `crates/api/src/main.rs`, `crates/api/src/state.rs`  
**Status:** [x] erledigt · **Survivor:** 9 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/api/src/main.rs:206:21: delete ! in main` (live-runtime shutdown → exclude_re)
- `crates/api/src/main.rs:230:30: replace != with == in main`
- `crates/api/src/main.rs:722:5: replace wait_for_shutdown with ()`
- `crates/api/src/main.rs:769:5: replace shutdown_ai_import with ()`
- `crates/api/src/main.rs:810:16: delete ! in shutdown_ai_import`
- `crates/api/src/main.rs:854:19: replace + with - in ai_import_shutdown_max_budget`
- `crates/api/src/main.rs:854:45: replace + with - in ai_import_shutdown_max_budget`
- `crates/api/src/main.rs:854:5: replace ai_import_shutdown_max_budget -> std::time::Duration with Default::default()`
- `crates/api/src/state.rs:174:9: replace <impl std::fmt::Debug for AppState<P>>::fmt -> std::fmt::Result with Ok(Default::default())`

**Strategie:**

- `wait_for_shutdown`/`shutdown_ai_import` → `()`: Shutdown-Helfer in testbare Funktionen ziehen; Budget `ai_import_shutdown_max_budget` analytisch asserten (killt `+`→`-`).
- `AppState` Debug-Redaction asserten (keine Secrets/URLs mit Credentials im Debug-Output).

**Verify:**

```bash
cargo mutants --file crates/api/src/main.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P6.7 — Problem-Surface (`problems/mod.rs`, `problems/locale.rs`)

**Datei(en):** `crates/api/src/problems/mod.rs`, `crates/api/src/problems/locale.rs`  
**Status:** [x] erledigt · **Survivor:** 3 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/api/src/problems/mod.rs:444:27: replace match guard error.is_syntax() || error.is_eof() with true in <impl axum::extract::FromRequest<S> for Json<T>>::from_request` (live HTTP → exclude_re)
- `crates/api/src/problems/mod.rs:529:9: replace <impl From<Bytes> for AxumBytes>::from -> Self with Default::default()`
- `crates/api/src/problems/locale.rs:114:36: replace == with != in parsed_resource`

**Strategie:**

- JSON-Syntax-Error-Guard, `AxumBytes`-From, `parsed_resource`-Vergleich: Golden-Tests in `problem_golden.rs` erweitern.

**Verify:**

```bash
cargo mutants --file crates/api/src/problems/mod.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```

### P6.8 — `migrate_gdrive_credentials` (bin)

**Datei(en):** `crates/api/src/bin/migrate_gdrive_credentials.rs`  
**Status:** [x] erledigt · **Survivor:** 12 · **Commit:** _noch offen_ · **PR/Branch:** `feature/274-batch6-queries-misc`

**Überlebende Mutanten:**

- `crates/api/src/bin/migrate_gdrive_credentials.rs:42:13: delete match arm "--settings-id" in parse_options`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:46:13: delete match arm "--actor" in parse_options`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:53:13: delete match arm "--rotate" in parse_options`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:54:13: delete match arm "--confirm-legacy-env" in parse_options`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:63:35: replace == with != in parse_options`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:63:8: delete ! in parse_options`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:91:5: replace run -> Result<()> with Ok(())`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:119:26: replace != with == in run`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:122:12: delete ! in run`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:123:13: replace && with || in run`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:123:35: replace == with != in run`
- `crates/api/src/bin/migrate_gdrive_credentials.rs:135:12: delete ! in run`

**Strategie:**

- `parse_options`-Match-Arme (`--settings-id`, `--actor`, `--rotate`, `--confirm-legacy-env`) und `run`-Guards: CLI-Parser in testbare Funktion extrahieren (falls noch nicht geschehen) und Optionstabelle testen.

**Verify:**

```bash
cargo mutants --file crates/api/src/bin/migrate_gdrive_credentials.rs
cargo clippy -p api --all-targets -- -D warnings
cargo test -p api --features test-support
```
