<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Übergabeprompt: Review-Fixes für den AI-Import-PR-Stack (#945/#946/#948/#949)

## Auftrag für die nächste Session

Arbeite die Findings **1–9** auf dem Top-Branch `feat/ai-import-reasoning-effort-settings`
(Commit `31d796dd`, PR #949) aus. Der gemeinsame Review-Bereich ist
`origin/main...HEAD`; derselbe Fix soll nicht in mehreren Stack-PRs unterschiedlich
nachgezogen werden. Finding 10 ist eine kleine Dokumentationskorrektur und darf direkt
mit erledigt werden.

Zuerst `AGENTS.md` im Monorepo und `backend/AGENTS.md` lesen, für Flutter zusätzlich
`frontend-flutter/AGENTS.md`. Code-Discovery über das Projekt `breakdown-rs` im
Knowledge Graph. Keine bezahlten Live-LLM-Tests und kein lokales Mutation-Testing
ausführen. Generierte Dateien (`vendor/breakdown_api/**`, `*.g.dart`,
`lib/l10n/generated/**`) nicht per Hand ändern.

**Vorhandene Nutzeränderungen schützen:** `frontend-flutter/pubspec.lock` war bereits
verändert. Die anderen `HANDOFF-*.md`-Dateien gehören nicht zu dieser Aufgabe. Keine
Dateien verwerfen oder zurücksetzen.

### Geprüfter Stack

- #945 `fix/ai-import-empty-completion-diagnostics` → `main`
- #946 `feat/ai-import-reasoning-effort` → #945
- #948 `feat/ai-import-reasoning-effort-config` → #946
- #949 `feat/ai-import-reasoning-effort-settings` → #948

## What this change does:

Der Stack behandelt leere LLM-Antworten als begrenzt wiederholbaren Providerfehler,
misst `reasoning_effort` an echten Drehbüchern und macht die Denk-Intensität je
Provider/Modell konfigurierbar. Das Feld läuft durch Aggregat, Events, Projection,
Worker, OpenAPI und Flutter. `auto` bedeutet dabei: zuerst das kuratierte Profil,
sonst der Provider-Default.

Angenommene Last: mehrere gleichzeitige Nutzer und Worker, externe **bezahlte** LLM-
Requests sowie ein Nightly mit bis zu 40 Requests pro Dokumentvariante. Ein unnötiger
Retry ist daher nicht nur eine Verzögerung, sondern verursacht reale Kosten.

## Must fix

### 1. Providerwechsel umgeht die Effort-Validierung

- **Ort:** `backend/crates/core/src/ai/aggregate.rs`, `UpdateAiConfig::handle`,
  besonders `effort_unchanged` um die aktuellen Zeilen 256–270.
- **What this is:** Ein unverändertes Provider/Modell/Effort-Tripel darf bei einem
  Prompt-only-Edit trotz Katalogrotation bestehen bleiben.
- **Problem:** `effort_unchanged` vergleicht nur Modell und Effort, **nicht den
  Provider**. Ein Providerwechsel mit neuem Vault-Key ist sonst ausdrücklich erlaubt.
  Dadurch wird genau dann nicht validiert, wenn sich das Provider/Modell-Paar ändert.
- **Konkreter Fall:**
  1. Gespeichert ist `Neuralwatt / glm-5.3 / minimal`; dort ist `minimal` erlaubt.
  2. PATCH auf `OpenCode / glm-5.3`, gleiches Modell, `reasoning_effort` weggelassen,
     neuer OpenCode-Vault-Key.
  3. `effort_unchanged == true`, obwohl OpenCode für dieses Modell nur `low|high`
     deklariert. Das Update wird akzeptiert; der Worker sendet später `minimal` und
     kann bei jedem Import einen HTTP-400 erhalten.
- **Fix (minimal):** den Provider in denselben Vergleich aufnehmen:

  ```rust
  let effort_unchanged = current_provider == cmd.provider
      && reasoning_effort == self.reasoning_effort
      && cmd.assistant_model == self.assistant_model;
  ```

  Die bestehende Rotation-Regel bleibt erhalten: nur ein **wirklich** unverändertes
  Tripel überspringt die erneute Validierung.
- **Pflicht-Regressionstest:** in `core/src/ai/aggregate_tests.rs` ein gespeichertes
  `Created`-Event mit `Neuralwatt / glm-5.3 / Minimal` replayen, danach Update auf
  `OpenCode / glm-5.3`, neuer Key, `reasoning_effort: None`. Erwartung:
  `AiConfigError::ReasoningEffortUnsupported`. Der bestehende gültige
  Providerwechsel-Test muss weiter grün bleiben.
- **If we skip it:** Die Save-time-422 hat einen direkten Bypass; ungültige
  Konfigurationen erreichen den Provider und verursachen wiederkehrende Fehler/Kosten.

### 2. Eine inhaltliche LLM-Ablehnung wird mehrfach bezahlt und als Providerausfall gezählt

- **Ort:** `backend/crates/infra/src/ai/client.rs`, `step_for_response`,
  aktuell ca. Zeilen 1382–1419.
- **What this is:** Leere Antworten mit Token-Truncation sollen mit größerem Budget
  erneut angefragt werden.
- **Problem:** Die Funktion behandelt **jede** leere Antwort gleich. Auch
  `message.refusal` oder ein Safety-`content_filter` führt durch alle inneren Retries
  und danach zu `ai-import.llm-provider-unavailable` (retryable, breaker-relevant).
  Mehr Budget ändert eine inhaltliche Ablehnung nicht.
- **Konkreter Fall:** `content: null`, `refusal: "cannot help with that"`,
  `finish_reason: "stop"`. Mit zwei freien inneren Retries werden drei gleichartige
  Requests bezahlt. Danach können weitere Attempt-Retries folgen und der Breaker kann
  einen eigentlich ablehnenden Request als Providerausfall markieren.
- **Fix (minimal):** vor dem Truncation-Branch eine nicht-leere `refusal` (und
  analog `finish_reason == "content_filter"`) als terminalen Validierungsfehler
  behandeln. Die vorhandene, auf 400 Zeichen begrenzte Diagnose weiterverwenden; kein
  neuer Problem-Code nötig. Kein Budget-Retry und kein Provider-Breaker für diesen Arm.
- **Pflicht-Regressionstests:**
  - Refusal mit `truncation_retries_left = 2` ergibt sofort `ResponseStep::Fail`,
    `!error.is_retryable()` und enthält weiterhin `refusal=...`.
  - `content_filter` ohne Refusal ergibt ebenfalls sofort einen terminalen Fehler.
  - Der vorhandene Test `a_null_content_is_retried...` bleibt unverändert grün: ein
    echtes `length` ohne Refusal wird weiterhin erneut versucht.
  - Finding 9 ergänzt den HTTP-Zähler: eine Refusal erzeugt genau **einen** Request.
- **If we skip it:** Safety-Ablehnungen kosten mehrfach Geld und können gesunde
  Provider/Modelle in einen Hold schicken.

### 3. Der Dokumentprobe-Nightly scheitert ohne optionale Variable am leeren Dateinamen

- **Ort:** `backend/crates/integration-tests/tests/ai_llm_smoke_test.rs`,
  `reasoning_effort_document_quality_and_cost`, aktuell ca. Zeile 1143;
  Workflow `.github/workflows/ai-import-nightly.yml`.
- **What this is:** Der Workflow übergibt optionale GitHub-`vars` immer als
  Environment-Variablen. Undefinierte Werte kommen als leerer String an.
- **Problem:** Der Single-Chunk-Probe nutzt bereits `env_non_empty`, die neue
  Whole-Document-Probe dagegen:

  ```rust
  let document_name =
      env::var("AI_LLM_PROBE_DOCUMENT").unwrap_or_else(|_| "292.pdf".to_owned());
  ```

  Mit gesetztem API-Key, aber ohne `vars.AI_LLM_PROBE_DOCUMENT` sucht der Test nach
  `""` statt `292.pdf`. Der Workflow-Log behauptet gleichzeitig den Default `292.pdf`.
- **Fix (minimal):** eine kleine reine Auflösungsfunktion in beiden Proben verwenden:

  ```rust
  fn probe_document_name(raw: Option<String>) -> String {
      non_empty(raw).unwrap_or_else(|| "292.pdf".to_owned())
  }
  // Aufruf: probe_document_name(env::var("AI_LLM_PROBE_DOCUMENT").ok())
  ```

  Die gleichartige Default-Stelle `AI_LLM_MODEL` in `live_llm()` ebenfalls auf
  `env_non_empty("AI_LLM_MODEL")` umstellen, damit auch der dort ausgegebene
  `mistral-large-3`-Default tatsächlich greift.
- **Pflicht-Regressionstest:** rein und ohne Prozess-Environment:
  `None`, `Some("")`, `Some("   ")` → `292.pdf`; `Some("293.pdf")` → `293.pdf`.
  Der bestehende Test von `non_empty` allein prüft den Call-Site-Fehler nicht.
- **If we skip it:** Der neue Nightly ist in seiner dokumentierten Standardkonfiguration
  rot bzw. prüft kein einziges Dokument.

### 4. Flutter versteckt eine gespeicherte, nicht mehr deklarierte Stufe bei nicht-leerem Picker

- **Ort:** `frontend-flutter/lib/features/ai_import/ai_config/ai_config_screen.dart`,
  `_ReasoningEffortSelector`, aktuell ca. Zeilen 1025–1090.
- **What this is:** Der PR verspricht für Katalogrotation den Hinweis
  „Gespeichert: <Stufe>“ ohne den unberührten Wert zurückzusetzen.
- **Problem:** Der Hinweis erscheint nur bei `declared.isEmpty`. Bei gespeichertem
  `minimal` und aktuell deklariertem `low|high` zeigt der Picker `auto|low|high`,
  `selected` bleibt aber `minimal`. Kein Segment ist sichtbar ausgewählt und der
  Hinweis fehlt. Der Nutzer kann die tatsächlich mitgespeicherte Einstellung nicht
  erkennen.
- **Fix (klein und ohne stillen Reset):**
  - `current = state.reasoningEffort` verwenden, nicht dauerhaft das alte `stored`.
  - Wenn `current != auto && !declared.contains(current)`, diesen Wert als
    **deaktiviertes**, ausgewähltes `ButtonSegment` ergänzen und den vorhandenen
    Stored-Hinweis zeigen. So bleibt `selected` konsistent und
    `emptySelectionAllowed` ist nicht nötig.
  - Sobald der Nutzer `auto` oder eine deklarierte Stufe wählt, verschwindet der
    Sonderzustand; erst diese bewusste Wahl verändert den PATCH.
- **Pflicht-Widgettest:** gespeichert `minimal`, Modell deklariert `[low, high]`.
  Erwarten: Stored-Hinweis sichtbar, deaktiviertes `minimal` ausgewählt, `low|high`
  und `auto` wählbar. Ein unverändertes Speichern überträgt weiterhin `minimal`.
  Danach `auto` wählen und den bestehenden Reset-PATCH prüfen.
- **If we skip it:** Die UI zeigt eine andere Konfiguration als der nächste PATCH und
  der zentrale Katalogrotations-Fall aus der PR-Beschreibung ist nicht umgesetzt.

## Should fix

### 5. „Modellliste unbekannt“ wird in Flutter als „Modell unterstützt nichts“ dargestellt

- **Ort:** `ai_config_controller.dart`, `declaredReasoningEfforts`, und
  `ai_config_screen.dart`, `_ReasoningEffortSelector`.
- **What this is:** `state.models.value` ist während Loading und nach einem
  Ladefehler `null`; `declaredReasoningEfforts` gibt dann wie bei echter fehlender
  Capability eine leere Menge zurück.
- **Problem:** Der Selector behauptet in beiden Fällen
  `aiConfigReasoningEffortUnavailable`. Ein 503 des Modellkatalogs wird damit zu einer
  falschen fachlichen Aussage über das Modell.
- **Fix:** Der Selector muss `AsyncData` von Loading/Error unterscheiden. Nur eine
  erfolgreich geladene Modellzeile mit leerer Capability darf den Unavailable-Text
  zeigen. Bei Loading/Error den Bereich neutral/ausgeblendet bzw. als unbekannt
  rendern und den gespeicherten Wert unverändert lassen; keine neue Modelltabelle.
- **Pflicht-Widgettest:** konfigurierte Stufe `high`, `modelsValue: Left(...)`.
  Erwartung: kein Unavailable-Text, kein automatischer Reset; Prompt-only-PATCH
  überträgt weiterhin `high`. Ein Loading-Zustand darf dieselbe falsche Aussage nicht
  zeigen.
- **If we skip it:** Ein vorübergehender Katalogfehler wird als dauerhafte
  Produktentscheidung angezeigt.

### 6. `GDRIVE_ROOT` wird zweimal in Logs geschrieben

- **Ort:** `.github/workflows/ai-import-nightly.yml` (`echo "GDRIVE_ROOT=..."`) und
  `backend/crates/integration-tests/tests/ai_llm_smoke_test.rs`
  (`root = %gdrive.root` beim Fixture-Listing).
- **What this is:** `GDRIVE_ROOT` kommt aus GitHub Secrets und identifiziert den
  internen Fixture-Ordner.
- **Problem:** Der volle Wert wird in CI- und Testlogs ausgegeben. GitHub-Masking ist
  ein Schutz, keine Rechtfertigung für absichtliches Secret-Logging; lokale Logs haben
  dieses Masking nicht.
- **Fix:** Beide Wert-Ausgaben löschen. Die Fixture-Namen und Dokumentanzahl reichen
  zur Diagnose. Danach mit Text-Suche prüfen:

  ```bash
  rg -n 'GDRIVE_ROOT=|root = %gdrive\.root' \
    .github/workflows/ai-import-nightly.yml \
    backend/crates/integration-tests/tests/ai_llm_smoke_test.rs
  ```

- **If we skip it:** Interne Storage-Koordinaten bleiben dauerhaft in Logs stehen.

### 7. Der Nicht-`Auto`-Pfad ist nicht durch API, Event-Replay und Projection getestet

- **Ort:** `backend/crates/api/tests/handler_ai_import_ports.rs`,
  `backend/crates/integration-tests/tests/ai_config_decision_projection.rs`,
  `backend/crates/core/src/ai/events.rs`.
- **What this is:** Die neuen Aggregate-Tests prüfen Events, die Widgettests prüfen
  Dart-Requestobjekte. Der bestehende Tier-4-Test verwendet ausschließlich `Auto`
  und enthält keine Assertion auf `reasoning_effort`.
- **Problem:** Ein Verlust des konkreten Levels in Handler → Command → Event →
  Projector → SQL → `AiConfigView`/`AiWorkerConfig` kann bei komplett grüner Suite
  auftreten. Ebenso fehlt ein direkter Replay-Vertrag für alte Events ohne das neue
  Feld; dort würde ein Fehler erst als Projection-Dead-Letter sichtbar.
- **Fix/Tests:**
  1. **API:** einen gültigen expliziten Wert (`Low`) durch Create und Update bis zum
     aufgezeichneten Command prüfen. Einen ungültigen Wert als RFC-9457-Fehler mit
     HTTP 422 und `code == "ai-config.reasoning-effort-unsupported"` prüfen.
  2. **Tier 4:** im bestehenden Projectionstest z. B.
     `EXTRACTION_MODEL = "mistral-small-4"` und Create mit
     `ReasoningEffortChoice::Low` verwenden. Auf `Low` in der SQL-Spalte,
     `find_by_id(...).reasoning_effort` **und**
     `find_worker_config(...).reasoning_effort` warten/prüfen. Nicht nur auf Zeilen-
     Existenz warten.
  3. **Replay:** alte JSON-Payloads von `Created` und `Updated` ohne
     `reasoning_effort` deserialisieren und `Auto` assertieren. Keine neuen Fixtures
     nötig; zwei kleine JSON-Literale genügen.
- **If we skip it:** Genau der produktive, vom Nutzer gewählte Wert ist ohne
  Ende-zu-Ende-Schutz.

### 8. Script- und Schedule-Worker haben ungetestete, doppelte Default-Auflösung

- **Ort:** `backend/crates/infra/src/ai/workers.rs`, Requestbau ca. Zeilen 760 und
  1670; `backend/crates/infra/src/ai/tests.rs`.
- **What this is:** Beide Worker berechnen derzeit getrennt:
  explizite Stufe → kuratiertes Default (`glm-5.3-flash = low`) → kein Feld.
- **Problem:** Kein Worker-Test prüft den tatsächlich an `LlmClient` übergebenen
  `reasoning_effort`. Das Entfernen des Feldes in einem oder beiden Requestbauern
  bliebe unentdeckt. Die beiden identischen Auflösungsblöcke müssen außerdem bei
  jeder späteren Regeländerung gemeinsam gepflegt werden.
- **Fix (merge statt neue Schicht):** eine kleine private Funktion in `workers.rs`:

  ```rust
  fn resolved_reasoning_effort(
      provider: LlmProvider,
      model: &str,
      choice: ReasoningEffortChoice,
  ) -> Option<ReasoningEffort> {
      choice
          .effort()
          .or_else(|| default_reasoning_effort(provider, model))
  }
  ```

  Beide Worker nutzen sie. Die Matrix einmal rein testen:
  - explizit `High` auf `glm-5.3-flash` → `High` (explizit schlägt kuratiertes `Low`),
  - `Auto` auf `glm-5.3-flash` → `Low`,
  - `Auto` auf einem unprofilierten Modell → `None`.

  Zusätzlich je ein Worker-Test für Script und Schedule, der den Request recorded.
  Vorhandene Fakes erweitern statt eine dritte Fake-Familie zu bauen. Der bereits
  vorhandene Serialisierungstest in `client_tests.rs` prüft `Some("low")` und `None`
  im JSON und muss bleiben.
- **If we skip it:** Die Kernfunktion kann in genau einem der beiden Importpfade
  still verschwinden oder abweichen.

### 9. Die Empty-Completion-Tests stoppen vor der echten HTTP-Requestschleife

- **Ort:** `backend/crates/infra/src/ai/client.rs` und `client_tests.rs`.
- **What this is:** `step_for_response` ist gut isoliert getestet. Der neue Code um
  ihn herum entscheidet aber erst über erneute Requests, Budgetwerte, Usage-Summe und
  die tatsächliche Requestanzahl.
- **Problem:** Kein lokaler Test beweist derzeit die Sequenz
  `HTTP 200/content=null` → zweiter Request mit doppeltem Budget → gültiges JSON.
  Auch die summierte Usage beider bezahlter Antworten und „Refusal = genau ein
  Request“ (Finding 2) werden nicht durch den Transport geprüft.
- **Fix/Test:** die bereits vorhandene Dev-Dependency `wiremock` verwenden; keine neue
  Dependency. Einen engen Test-Endpoint-Seam ergänzen, ohne die produktive
  Provider-URL-Allowlist aufzuweichen. Zwei Response-Mocks:
  1. `content: null`, `finish_reason: "length"`, Usage A;
  2. gültiges `ScriptContext`-JSON, Usage B.

  Asserts: zwei Requests, `max_tokens` 8192 dann 16384, gültiges Ergebnis,
  `outcome.usage == A + B`. Für Refusal: nur ein Request und terminaler Fehler.
- **If we skip it:** Die reine Funktion ist grün, während ein Fehler in ihrer
  produktiven Verdrahtung unbemerkt bleibt.

## Nice to have

### 10. Kommentare beschreiben teilweise das verworfene `Option`-Design statt `Auto`

- **Ort:** `core/src/ai/aggregate.rs` (`validate_reasoning_effort`),
  `core/src/ai/commands.rs`, und
  `infra/migrations/20261120000001_ai_config_reasoning_effort.up.sql`.
- **What this is:** Die Implementierung sagt `Auto = kuratiertes Profil, sonst
  Provider-Default`. Einige Kommentare sagen noch `None/Some` bzw. nur
  „Provider-Default“; die Decision-Model-Doku steht zusätzlich direkt über der
  Reasoning-Funktion.
- **Fix:** Kommentare auf `ReasoningEffortChoice::Auto` und die tatsächliche
  Vorrangreihenfolge korrigieren; die Decision-Doku wieder an
  `validate_decision_config` setzen. Kein Verhalten ändern.
- **If we skip it:** Der nächste Maintainer kann aus den Kommentaren eine falsche
  Wire-/Default-Semantik ableiten.

## Rust- und `Arc<T>`-Leitplanken für die Umsetzung

Der Review hat **keine neu eingeführte `Arc<T>`-Fehlverwendung** gefunden. Die neue
`ReasoningEffortChoice` ist zu Recht ein kleiner `Copy`-Wert und kein `Arc`. Die
bestehenden `Arc<Q>`/`Arc<C>` in den Workern bleiben für geteilte Queues/Clients
sinnvoll.

Bei den Fixes bitte typische LLM-`Arc`-Fehler vermeiden:

- **Nicht** `ReasoningEffortChoice`, `ReasoningEffort`, `ResponseMeta` oder
  `LlmChatRequest` in `Arc` packen. Das sind kleine Werte bzw. pro Request bewegte
  Daten. Borrowing (`&Q`, `&C`, `&LlmChatRequest`) reicht, solange keine geteilte
  Ownership nötig ist.
- **Nicht** `Arc<Arc<T>>` erzeugen und nicht pauschal `.clone()` auf jedem Workerfeld
  aufrufen. Wenn wirklich geteilte Ownership nötig ist, `Arc::clone(&arc)` verwenden;
  für einen kurzen Aufruf `queue.as_ref()`/`client.as_ref()`.
- Test-Recorder dürfen `Arc<Mutex<Vec<LlmChatRequest>>>` verwenden, weil Fake und Test
  dieselbe Aufzeichnung teilen. Das ist ein Testgrund, kein Grund, die Produktions-
  Requests selbst in `Arc` zu ändern.
- Die Effort-Auflösung als `Option<ReasoningEffort>` berechnen und erst beim
  Requestbau in den vorhandenen Wire-String umwandeln. Keine neue Arena, kein globales
  Cache-Objekt und keine zusätzliche Abhängigkeit für diese vier Zeilen.
- Produktiv keine `unwrap`/`expect`/Panics einführen. Test-Panics bleiben in den
  bestehenden Testmodulen zulässig.

## Empfohlene Arbeitsreihenfolge

1. Finding 1 + Regressionstest (Domain-Korrektheit).
2. Finding 2 + Finding 9 (Retry-Verhalten und reale HTTP-Schleife gemeinsam testen).
3. Finding 3 + reine Default-Tests.
4. Findings 4–5 + Widgettests.
5. Finding 6 (zwei Logzeilen entfernen).
6. Findings 7–8 (Persistenz-/Worker-Harness und Zusammenfassung der Doppelung).
7. Finding 10, Formatierung, SPDX-/Co-Author-Header für tatsächlich neue Dateien.
8. Erst danach PR-/Stack-Beschreibung aktualisieren; insbesondere die Behauptung, der
   Katalogrotations-Fall sei durch UI und Tests abgedeckt, erst nach Finding 4/5
   erneut prüfen.

## Abnahmekommandos

Im Backend:

```bash
cargo fmt --check
cargo test -p breakdown_core ai::
cargo test -p infra --lib ai::client::tests
cargo test -p infra --lib ai::provider_registry::tests
cargo test -p infra --lib ai::tests
cargo test -p api --test handlers_ai
cargo test -p integration-tests --test ai_config_decision_projection
# Nur Offline-Smoke/Arithmetik; bewusst ohne bezahlte Credentials:
env -u AI_LLM_API_KEY -u AI_LLM_PROBE_API_KEY \
  cargo test -p integration-tests --test ai_llm_smoke_test -- --nocapture
cargo clippy --workspace --all-targets -- -D warnings
```

Im Flutter-Bereich:

```bash
cd ../frontend-flutter
flutter analyze
flutter test test/features/ai_import/ai_config_screen_test.dart
```

Nicht lokal ausführen: `cargo mutants`, echte Nightly-/Live-Provider-Aufrufe. OpenAPI
und generierte Clients nur neu erzeugen, falls die Umsetzung den Vertrag ändert; die
hier vorgeschlagenen Fixes benötigen keine Vertragsänderung.

## Bereits im Review ausgeführt

- `cargo test -p breakdown_core ai::` → **419 passed**.
- `cargo test -p infra --lib ai::client::tests` → **10 passed**.
- `cargo test -p infra --lib ai::provider_registry::tests` → **16 passed**.
- `env -u AI_LLM_API_KEY -u AI_LLM_PROBE_API_KEY cargo test -p integration-tests
  --test ai_llm_smoke_test -- --nocapture` → **9 passed**, davon vier Live-Tests
  ausdrücklich ohne Assertion übersprungen.
- `flutter test test/features/ai_import/ai_config_screen_test.dart` → **96 passed**.

Diese grünen Ergebnisse widerlegen die Findings nicht: die oben genannten Fälle sind
in den aktuellen Fixtures gerade nicht enthalten.

## Verdict und Prüfgrenzen

**Verdict: fix 1–9 vor dem Merge; Finding 10 gleich mitnehmen.**

**Lean:** durch die gemeinsame Effort-Auflösung und das Löschen der zwei Wert-Logs
sind ungefähr **8–10 Zeilen** weniger bzw. doppelt gepflegter Code möglich; keine neue
Framework-Schicht.

**Not checked:** keine bezahlten Provider- oder GitHub-Nightly-Aufrufe, keine echte
Deployment-Migration, keine visuelle Neubeurteilung der binären Golden-PNGs. Der
Review las den vollständigen Stack-Diff und die betroffenen Produktions-/Testpfade;
Graph-Coverage wurde für die Belegpfade geprüft, Flutter-Belegstellen zusätzlich direkt
gelesen.
