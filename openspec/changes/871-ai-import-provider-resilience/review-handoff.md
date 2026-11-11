<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Handoff-Prompt: Review-Findings für Issue #871 (Workstreams B & C) abarbeiten

Du arbeitest im Repository `breakdown-rs` (Arbeitsverzeichnis `backend/`) auf dem Branch `feature/871-c-retry-policy`.
Deine Aufgabe ist es, **alle 6 Review-Findings** aus dem Code-Review zu Issue #871 (Chunk-Level Resume & Retry Policy) präzise, minimal-invasiv und vollständig getestet umzusetzen.

## 0. Verbindliche Leitplanken (vorab lesen und strikt einhalten)

1. **Keine Panics im Produktionscode (`AGENTS.md §3`):** Kein `.unwrap()`, `.expect()`, `panic!()`, `unreachable!()`, `todo!()` in `crates/infra/src/**` außerhalb von `#[cfg(test)]`.
2. **Keine String-Interpolation in SQL (`AGENTS.md §3`):** Alle SQL-Statements in `sqlx::query*` müssen statische String-Literale sein; Parameter ausschließlich über `.bind(...)`.
3. **Keine verworfenen `Result`s (`AGENTS.md §3`):** Kein `let _ = ...` auf fehlbaren Aufrufen (`discard-result`-Regel).
4. **Keine Wall-Clock-Sleeps in Tests (`AGENTS.md §4`):** Tests prüfen Call-Counts, gespeicherte Zustände und deterministische Invarianten – niemals echte Wartezeiten.
5. **Tooling-Disziplin (`AGENTS.md §2`):** Nutze `get_code_snippet` / `read` mit gezieltem `offset`/`limit` vor jedem `edit`. Falls `edit` wegen Whitespace/Filterung fehlschlägt, deaktiviere kurzzeitig `rtk_configure(sourceCodeFilteringEnabled: false)`, lies den Abschnitt neu ein, wende `edit` an und aktiviere den Filter wieder.

---

## 1. Finding 1 & 2 & 6b: `ScriptImportWorker::process_text`, `open_chunk_set` und `hold_job` (`backend/crates/infra/src/ai/workers.rs` + `worker_loop.rs`)

### Warum (Problembeschreibung)
1. **Finding 1 (Progress-Rewind & doppelte `done_bytes` bei Resume):**
   In `ScriptImportWorker::process_text` (`crates/infra/src/ai/workers.rs`) wird vor der Chunk-Schleife bei `resumed_from > 0` bereits `progress.chunk = Some(resumed_from)` und `progress.record_done_bytes(sum(0..resumed_from))` gesetzt und publiziert (`L679-703`).
   In der anschließenden Schleife über **alle** Chunks (`0..chunk_count`) passiert für bereits gespeicherte Chunks (`resumed_chunk.is_some()`, also Index `0..resumed_from`) aktuell Folgendes:
   - Oben in der Schleife (`L737`) wird `!gate.admits().await` geprüft, obwohl für einen gespeicherten Chunk **kein** Provider-Request stattfindet. Sind sogar schon alle Chunks gespeichert, würde ein offener Breaker den Job grundlos vor dem Merge parken.
   - Unten in der Schleife (`L1071-1081`) wird für jeden gespeicherten Chunk `progress.chunk = Some(chunk_index + 1)` überschrieben (springt von `25` zurück auf `1`), `progress.record_done_bytes(...)` ein **zweites Mal** aufaddiert und `publish_progress(...)` aufgerufen.
2. **Finding 2 (`chunks_done: 0` in `hold_job`):**
   `hold_job` (`crates/infra/src/ai/workers.rs:L4194-4229`) setzt `chunks_done: 0` noch hartcodiert aus PR A. Wenn der Breaker mitten im Lauf bei Chunk `index` öffnet, geht die Anzahl der bereits gespeicherten Chunks im `ProviderHold` verloren.
3. **Finding 6b (Doppeltes `tracing::warn!` bei Invalidation):**
   Sowohl `PgAiImportChunkStore::begin_extraction_locked` (`chunk_store.rs:L146`) als auch `ScriptImportWorker::open_chunk_set` (`workers.rs:L499`) loggen bei `ChunkSetState::Invalidated` fast identisch `#871 chunk resume invalidated`. Behalte nur das Log in `chunk_store.rs` (das zusätzlich `deleted_chunks` enthält).

### Exakte Änderungen in `backend/crates/infra/src/ai/workers.rs`

#### Schritt 1a: Doppeltes Warn-Log in `open_chunk_set` (`crates/infra/src/ai/workers.rs:L495-503`) entfernen
Lies `crates/infra/src/ai/workers.rs` um Zeile 478–523 und ersetze in `open_chunk_set`:

**Vorher:**
```rust
        let key = super::chunk_store::fingerprint_key(&fingerprint);
        if let ChunkSetState::Invalidated(components) = store
            .begin_extraction(job.id, worker_id, &fingerprint, &key)
            .await?
        {
            tracing::warn!(
                job_id = %job.id.as_uuid(),
                components = ?components,
                "#871 chunk resume invalidated: the stored chunks belong to a different configuration"
            );
        }
        let stored_chunks = store.load(job.id).await?;
```

**Nachher:**
```rust
        let key = super::chunk_store::fingerprint_key(&fingerprint);
        // `begin_extraction` logs `#871 chunk resume invalidated` (with
        // `components` and `deleted_chunks`) when it drops a mismatched set.
        let _state: ChunkSetState = store
            .begin_extraction(job.id, worker_id, &fingerprint, &key)
            .await?;
        let stored_chunks = store.load(job.id).await?;
```
*(Wichtig: Binde an `let _state = ...` und verwende niemals `let _ =` auf einem `Result`, wegen der `discard-result`-Regel!)*

#### Schritt 1b: Episoden des gespeicherten Präfixes vor dem ersten Frame erfassen (`crates/infra/src/ai/workers.rs:L679-704`)
Lies `crates/infra/src/ai/workers.rs` um Zeile 675–715.
Damit der initiale Progress-Frame bei einem Resume schon alle Episoden aus `0..resumed_from` kennt (und wir unten in der Schleife für gespeicherte Chunks kein `publish_progress` mehr auslösen müssen), aktualisiere den Block vor der Schleife:

**Vorher:**
```rust
        if resumed_from > 0 {
            // The bar must not snap back to zero (D-B5): the first frame already
            // reports the stored prefix, and `resumed_from` is what lets a client
            // derive a rate from `chunk - resumed_from` instead of reading 25
            // chunks in one second.
            progress.chunk = Some(resumed_from);
            progress.resumed_from = Some(resumed_from);
            // The bytes of the resumed chunks are already extracted, so the byte
            // numerator starts where the stored prefix ends.
            progress.record_done_bytes(
                chunks_bytes
                    .iter()
                    .take(resumed_from as usize)
                    .copied()
                    .fold(0u64, u64::saturating_add),
            );
            tracing::info!(
                job_id = %job.id.as_uuid(),
                resumed_from,
                chunks = chunk_count,
                "#871 chunk resume: continuing at the first uncompleted chunk"
            );
        }
        if let Some(first) = chunks.first() {
            progress.record_episode(first.episode.as_ref());
        }
        super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
```

**Nachher:**
```rust
        if resumed_from > 0 {
            // The bar must not snap back to zero (D-B5): the first frame already
            // reports the stored prefix, and `resumed_from` is what lets a client
            // derive a rate from `chunk - resumed_from` instead of reading 25
            // chunks in one second.
            progress.chunk = Some(resumed_from);
            progress.resumed_from = Some(resumed_from);
            // The bytes and episodes of the resumed chunks are already known, so
            // the first frame starts where the stored prefix ends.
            progress.record_done_bytes(
                chunks_bytes
                    .iter()
                    .take(resumed_from as usize)
                    .copied()
                    .fold(0u64, u64::saturating_add),
            );
            for resumed_chunk in chunks.iter().take(resumed_from as usize) {
                progress.record_episode(resumed_chunk.episode.as_ref());
            }
            tracing::info!(
                job_id = %job.id.as_uuid(),
                resumed_from,
                chunks = chunk_count,
                "#871 chunk resume: continuing at the first uncompleted chunk"
            );
        }
        if let Some(first) = chunks.first() {
            progress.record_episode(first.episode.as_ref());
        }
        super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
```

#### Schritt 1c: In der Chunk-Schleife `gate.admits()` und Progress-Update nur für **neue** Chunks (`resumed_chunk.is_none()`) ausführen & `index` an `hold_job` übergeben (`crates/infra/src/ai/workers.rs:L728-760` und `L1050-1085`)
Lies `crates/infra/src/ai/workers.rs` um Zeile 725–765 sowie Zeile 1050–1085.

1. Oben in der Schleife (`L728-760`): Bestimme zuerst `index` und `resumed_chunk = stored.get(&index)`. Prüfe `!gate.admits().await` **nur im `None`-Zweig** (wenn tatsächlich ein Provider-Call ansteht) und übergib `index` als `chunks_done` an `hold_job`:

**Vorher:**
```rust
            if super::heartbeat::claim_lost(heartbeat.as_ref()) {
                // Stop before the next paid call: another worker owns the job.
                return Err(claim_lost_error(job.id, worker_id));
            }
            // Issue #871 (D-A5): the chunk boundary is the mid-run abort point.
            // The in-flight request is NOT aborted (an aborted HTTP request is
            // not refunded), so the only honest saving is not starting the next
            // one — the overspend bound is exactly one chunk per worker.
            if !gate.admits().await {
                hold_job(self.queue.as_ref(), &self.bounds, job.id, worker_id, &gate).await?;
                return Ok(String::new());
            }
            let index = u32::try_from(chunk_index).map_err(|error| {
                DomainError::validation(format!("script chunk index exceeds range: {error}"))
            })?;
            // Issue #871 (D-B3): a chunk inside the stored prefix was already
            // paid for and already produced its rows — resume it from the store
            // instead of asking (and paying) again. It is fed through the SAME
            // merge body below, so a resumed attempt assembles an identical
            // preview.
            let resumed_chunk = stored.get(&index);
            let call_result = match resumed_chunk {
                Some(stored_chunk) => Ok((stored_chunk.payload.clone(), stored_chunk.usage)),
                None => {
                    retry_chat(
                        self.client.as_ref(),
                        request,
                        self.bounds.max_attempt_retries as usize,
                        &gate,
                    )
                    .await
                }
            };
```

**Nachher:**
```rust
            if super::heartbeat::claim_lost(heartbeat.as_ref()) {
                // Stop before the next paid call: another worker owns the job.
                return Err(claim_lost_error(job.id, worker_id));
            }
            let index = u32::try_from(chunk_index).map_err(|error| {
                DomainError::validation(format!("script chunk index exceeds range: {error}"))
            })?;
            // Issue #871 (D-B3): a chunk inside the stored prefix was already
            // paid for and already produced its rows — resume it from the store
            // instead of asking (and paying) again. It is fed through the SAME
            // merge body below, so a resumed attempt assembles an identical
            // preview.
            let resumed_chunk = stored.get(&index);
            let call_result = match resumed_chunk {
                Some(stored_chunk) => Ok((stored_chunk.payload.clone(), stored_chunk.usage)),
                None => {
                    // Issue #871 (D-A5): the chunk boundary before a PAID call is
                    // the mid-run abort point. Stored prefix chunks make no call,
                    // so they never consult the breaker.
                    if !gate.admits().await {
                        hold_job(
                            self.queue.as_ref(),
                            &self.bounds,
                            job.id,
                            worker_id,
                            &gate,
                            index,
                        )
                        .await?;
                        return Ok(String::new());
                    }
                    retry_chat(
                        self.client.as_ref(),
                        request,
                        self.bounds.max_attempt_retries as usize,
                        &gate,
                    )
                    .await
                }
            };
```

2. Unten in der Schleife (`L1050-1085`): Übergib `index` an `hold_job` im `Err`-Zweig und führe das Progress-Update am Schleifenende **nur aus, wenn `resumed_chunk.is_none()`** ist:

**Vorher:**
```rust
                Err(error) => {
                    // Issue #871: the gate can refuse mid-attempt — from the top
                    // of `retry_bounded`, from the pre-sleep re-check, or from the
                    // client-internal guard. That is a HOLD, never a failure:
                    // `mark_failed` would charge a retry (and, because the sentinel
                    // is not `ServiceUnavailable`, dead-letter the job outright) for
                    // a call the breaker prevented.
                    if is_breaker_open(&error) {
                        hold_job(self.queue.as_ref(), &self.bounds, job.id, worker_id, &gate)
                            .await?;
                        return Ok(String::new());
                    }
                    self.fail(job.id, worker_id, &error).await?;
                    return Err(error);
                }
            }
            // Chunk completed (issue #664): 1-based counter + episodes
            // discovered up to and including this chunk, in first-seen order.
            progress.chunk = Some(u32::try_from(chunk_index + 1).map_err(|error| {
                DomainError::validation(format!(
                    "script chunk index exceeds telemetry range: {error}"
                ))
            })?);
            progress.record_episode(chunk.episode.as_ref());
            // Issue #762: count the bytes just extracted, so the published
            // numerator advances with the same cadence as the chunk counter.
            progress.record_done_bytes(chunks_bytes.get(chunk_index).copied().unwrap_or(0));
            super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
        }
```

**Nachher:**
```rust
                Err(error) => {
                    // Issue #871: the gate can refuse mid-attempt — from the top
                    // of `retry_bounded`, from the pre-sleep re-check, or from the
                    // client-internal guard. That is a HOLD, never a failure:
                    // `mark_failed` would charge a retry (and, because the sentinel
                    // is not `ServiceUnavailable`, dead-letter the job outright) for
                    // a call the breaker prevented.
                    if is_breaker_open(&error) {
                        hold_job(
                            self.queue.as_ref(),
                            &self.bounds,
                            job.id,
                            worker_id,
                            &gate,
                            index,
                        )
                        .await?;
                        return Ok(String::new());
                    }
                    self.fail(job.id, worker_id, &error).await?;
                    return Err(error);
                }
            }
            // Stored prefix chunks were already reflected in the initial frame
            // (`chunk = resumed_from`, `done_bytes = sum(0..resumed_from)`):
            // re-publishing them here would rewind `chunk` to `1..=resumed_from`
            // and double-count their bytes.
            if resumed_chunk.is_none() {
                // Chunk completed (issue #664): 1-based counter + episodes
                // discovered up to and including this chunk, in first-seen order.
                progress.chunk = Some(u32::try_from(chunk_index + 1).map_err(|error| {
                    DomainError::validation(format!(
                        "script chunk index exceeds telemetry range: {error}"
                    ))
                })?);
                progress.record_episode(chunk.episode.as_ref());
                // Issue #762: count the bytes just extracted, so the published
                // numerator advances with the same cadence as the chunk counter.
                progress.record_done_bytes(chunks_bytes.get(chunk_index).copied().unwrap_or(0));
                super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress)
                    .await?;
            }
        }
```

#### Schritt 1d: `hold_job`-Signatur und die weiteren Aufrufstellen aktualisieren (`crates/infra/src/ai/workers.rs` & `crates/infra/src/ai/worker_loop.rs`)
1. In `crates/infra/src/ai/workers.rs` um Zeile 4194–4229 (`hold_job`):
   Füge `chunks_done: u32` als Parameter hinzu und übernimm ihn in `ProviderHold`:
   ```rust
   pub(super) async fn hold_job<Q: AiImportQueue + ?Sized>(
       queue: &Q,
       bounds: &AiImportBounds,
       id: AiImportJobId,
       worker_id: &str,
       gate: &ProviderGate<'_, Q>,
       chunks_done: u32,
   ) -> Result<(), DomainError> {
       ...
       let hold = ProviderHold {
           provider: gate.provider,
           model: gate.model.to_string(),
           reason_code: "ai-import.llm-provider-unavailable".to_string(),
           state: breaker.state,
           until,
           hold_deadline: until
               + chrono::Duration::seconds(
                   i64::try_from(bounds.max_provider_hold_secs).unwrap_or(i64::MAX),
               ),
           chunks_done,
       };
       queue
           .mark_held(id, worker_id, hold, bounds.max_provider_hold_secs)
           .await
   }
   ```
   Aktualisiere auch den Doc-Kommentar über `hold_job` (entferne den veralteten Satz `` `chunks_done` is `0` in this build ``).
2. In `ScheduleImportWorker::process` (`crates/infra/src/ai/workers.rs` um Zeile 1560 und 1592):
   Ein Schedule-Job ist eine einzelne Extraktionseinheit (kein Chunk-Resume), übergib an beiden `hold_job(...)`-Aufrufen `0` als letztes Argument.
3. In `hold_if_breaker_open` (`crates/infra/src/ai/worker_loop.rs` um Zeile 240–250):
   Bestimme `chunks_done` aus `deps.chunks` (falls vorhanden und `job.document_kind == DocumentKind::Script`), damit auch ein vor dem Lauf geparkter Retry-Job seinen bereits gespeicherten Fortschritt behält:
   ```rust
   let chunks_done = match &deps.chunks {
       Some(store) if job.document_kind == DocumentKind::Script => store
           .load(job.id)
           .await
           .map(|chunks| breakdown_core::ai::resume_cursor(&chunks))
           .unwrap_or(0),
       _ => 0,
   };
   hold_job(
       deps.queue.as_ref(),
       &deps.bounds,
       job.id,
       worker_id,
       &gate,
       chunks_done,
   )
   .await?;
   ```

---

## 2. Finding 3: Unit-Test für `ScriptImportWorker` mit `chunks: Some(...)` ergänzen (`backend/crates/infra/src/ai/tests.rs`)

### Warum
Task 5.6 aus `tasks.md` fordert:
> Unit test with a fake `LlmClient`: a job with stored chunks `1..=25` issues exactly `chunks_total − 25` calls and never re-asks for `1..=25` (call count, not wall clock) (D-B6).

Aktuell setzen alle Worker-Tests in `crates/infra/src/ai/tests.rs` `chunks: None`.

### Exakte Umsetzung in `backend/crates/infra/src/ai/tests.rs`
Lies das Ende von `crates/infra/src/ai/tests.rs`. Füge dort einen deterministischen Unit-Test hinzu, der:
1. Einen leichtgewichtigen In-Memory-`AiImportChunkStore` implementiert (z. B. `InMemoryChunkStore` mit `Mutex<Vec<StoredChunk>>`, der `load`, `begin_extraction`, `put` und `clear` implementiert).
2. Einen `InMemoryQueue`-Job und ein Skript mit z. B. 4 Szenen-Headings (`INT. SCENE 1 - DAY` bis `INT. SCENE 4 - DAY`) vorbereitet, bei dem die ersten 2 Chunks (`chunk_index = 0` und `1`) bereits im `InMemoryChunkStore` liegen (mit je `tokens_in: 100`).
3. Einen `CountingLlmClient` nutzt, der die übergebenen `source_text`-Prompts aufzeichnet und pro Call `tokens_in: 50` zurückgibt.
4. `ScriptImportWorker` mit `chunks: Some(Arc::clone(&chunk_store))` aufruft (`worker.process_text(&job, "w-resume", script_text).await.unwrap()`).
5. Folgende 5 Punkte per `assert_eq!` prüft:
   - **Call-Count:** Der `CountingLlmClient` wurde exakt `2`-mal aufgerufen (`4 - 2 = 2`), und keiner der Aufrufe enthielt `SCENE 1` oder `SCENE 2`.
   - **Vollständige Preview:** Alle 4 Szenen sind im gespeicherten Preview enthalten.
   - **Kosten-/Token-Summe (D-B4):** Die aufgezeichnete Worker-Telemetrie summiert die gespeicherten Chunks (`2 × 100`) plus die neuen Calls (`2 × 50`) zu `tokens_in == 300`.
   - **Monotone Progress-Frames (Regressionstest für Finding 1):** Jeder während `Extracting` publizierte Progress-Frame hat `resumed_from == Some(2)`, `chunk >= Some(2)` (kein Rücksprung auf `1`!), und auf dem ersten Frame nach dem ersten neuen Chunk (`chunk == Some(3)`) ist `done_bytes` exakt die Byte-Summe der Chunks `0..3` (nicht doppelt gezählt!).
   - **Mid-run Hold `chunks_done` (Regressionstest für Finding 2):** Ein kurzer zweiter Test (oder Teilabschnitt), bei dem der Breaker nach 2 gespeicherten Chunks vor Chunk 3 offen ist und `mark_held` mit `hold.chunks_done == 2` aufgerufen wird.

---

## 3. Finding 4: Chunk-Rows beim Hold-Expiry (`expire_provider_holds`) löschen (`backend/crates/infra/src/ai/queue.rs` + Integration-Test)

### Warum
`mark_succeeded`, `mark_failed` (im `dead_letter`-Fall) und `mark_payload_unavailable` löschen alle in derselben SQL-Anweisung via CTE `cleared AS (DELETE FROM ai_import.ai_import_job_chunk ...)` die Chunk-Zeilen des Jobs.
`expire_provider_holds` (`crates/infra/src/ai/queue.rs:L1480-1559`) überführt ebenfalls Jobs in den terminalen Status `dead_letter`, hat die `cleared`-CTE aber vergessen.

### Exakte Änderung in `backend/crates/infra/src/ai/queue.rs`
Lies `crates/infra/src/ai/queue.rs` um Zeile 1500–1550 und ergänze die `cleared`-CTE in `expire_provider_holds`:

**Vorher:**
```sql
            expired AS (
                UPDATE ai_import.ai_import_job AS job
                SET status = 'dead_letter',
                    last_error = LEFT($1, 1000),
                    next_attempt_at = NULL,
                    progress = NULL,
                    decision_telemetry = NULL,
                    -- KEPT, not nulled: the marker the client branches on.
                    provider_hold = jsonb_set(
                        provider_hold,
                        '{state}',
                        '"expired"'
                    ),
                    provider_hold_series_started_at = NULL,
                    worker_id = NULL,
                    lease_expires_at = NULL,
                    permit_id = NULL,
                    updated_at = now()
                FROM numbered
                WHERE job.id = numbered.id
                RETURNING job.id, job.retries, job.last_error, numbered.rn,
                    pg_notify('ai_import_job_events', job.id::text)
            )
            INSERT INTO ai_import.ai_import_job_attempt
```

**Nachher:**
```sql
            expired AS (
                UPDATE ai_import.ai_import_job AS job
                SET status = 'dead_letter',
                    last_error = LEFT($1, 1000),
                    next_attempt_at = NULL,
                    progress = NULL,
                    decision_telemetry = NULL,
                    -- KEPT, not nulled: the marker the client branches on.
                    provider_hold = jsonb_set(
                        provider_hold,
                        '{state}',
                        '"expired"'
                    ),
                    provider_hold_series_started_at = NULL,
                    worker_id = NULL,
                    lease_expires_at = NULL,
                    permit_id = NULL,
                    updated_at = now()
                FROM numbered
                WHERE job.id = numbered.id
                RETURNING job.id, job.retries, job.last_error, numbered.rn,
                    pg_notify('ai_import_job_events', job.id::text)
            ),
            -- Issue #871 (D-B1): hold expiry is terminal (`dead_letter`), so any
            -- chunks stored before the hold are deleted in the same statement.
            cleared AS (
                DELETE FROM ai_import.ai_import_job_chunk
                WHERE job_id IN (SELECT id FROM expired)
            )
            INSERT INTO ai_import.ai_import_job_attempt
```

Ergänze außerdem in `crates/integration-tests/tests/ai_import_chunk_resume.rs` in `terminal_transitions_drop_the_rows_and_a_retryable_failure_keeps_them` (oder als eigenen Testfall daneben) eine Prüfung, dass auch `expire_provider_holds` gespeicherte Chunk-Zeilen eines gehaltenen Jobs löscht.

---

## 4. Finding 5: Workstream-C-Konstanten aus `core` an den beiden `infra`-Aufrufstellen verdrahten (`backend/crates/infra/src/ai/workers.rs` & `worker_loop.rs`)

### Warum
Workstream C hat `MAX_ATTEMPT_BACKOFF_SECS` (`30`) und `OLLAMA_INNER_RETRIES` (`3`) in `breakdown_core::ai::bounds` deklariert, damit `attempt_worst_case_secs` und die Laufzeit dieselben Konstanten verwenden. Zwei Stellen in `infra` nutzen noch die alten Literale.

### Exakte Änderungen
1. In `crates/infra/src/ai/workers.rs:L4424-4428` (`retry_bounded`):
   **Vorher:**
   ```rust
   tokio::time::sleep(supervisor::compute_backoff(
       attempt,
       std::time::Duration::from_secs(30),
   ))
   .await;
   ```
   **Nachher:**
   ```rust
   tokio::time::sleep(supervisor::compute_backoff(
       attempt,
       std::time::Duration::from_secs(breakdown_core::ai::MAX_ATTEMPT_BACKOFF_SECS),
   ))
   .await;
   ```

2. In `crates/infra/src/ai/worker_loop.rs:L187-196` (`build_ollama_client`):
   **Vorher:**
   ```rust
   fn build_ollama_client(
       timeout: Duration,
       health: Option<&Arc<dyn breakdown_core::ai::ProviderHealth>>,
   ) -> Result<Arc<OllamaChatClient>, DomainError> {
       let mut client = OllamaChatClient::new(3, timeout)?;
   ```
   **Nachher:**
   ```rust
   fn build_ollama_client(
       timeout: Duration,
       health: Option<&Arc<dyn breakdown_core::ai::ProviderHealth>>,
   ) -> Result<Arc<OllamaChatClient>, DomainError> {
       let mut client =
           OllamaChatClient::new(breakdown_core::ai::OLLAMA_INNER_RETRIES, timeout)?;
   ```

---

## 5. Finding 6a: Unbenutzte Funktionen in `chunk_store.rs` löschen (`backend/crates/infra/src/ai/chunk_store.rs`)

### Warum
`pub async fn stored_fingerprint` (`crates/infra/src/ai/chunk_store.rs:L176-196`) und `pub fn payload_is_decodable` (`crates/infra/src/ai/chunk_store.rs:L404-406`) haben im gesamten Workspace null Aufrufer (weder im Produktionscode noch in Tests).

### Exakte Änderung in `backend/crates/infra/src/ai/chunk_store.rs`
1. Lies `crates/infra/src/ai/chunk_store.rs` um Zeile 170–200 und entferne `pub async fn stored_fingerprint(...)` samt Doc-Kommentar.
2. Lies `crates/infra/src/ai/chunk_store.rs` um Zeile 395–415 und entferne `pub fn payload_is_decodable(...)` samt Doc-Kommentar.
3. Prüfe oben in `crates/infra/src/ai/chunk_store.rs`, ob dadurch ein Import (z. B. `ScriptContext`) unbenutzt wird; falls ja, entferne den unbenutzten Import, damit `clippy -D warnings` sauber bleibt.

---

## 6. Verifikation & Abschluss-Checks

Führe nach den Edits im Verzeichnis `backend/` nacheinander folgende Befehle aus und stelle sicher, dass alle grün sind:

1. **Formatierung & Compiler & Clippy:**
   ```bash
   cargo fmt --all -- --check
   cargo clippy --workspace --all-targets --all-features -- -D warnings
   ```
2. **Unit-Tests in `core` und `infra`:**
   ```bash
   cargo test -p breakdown_core ai::
   cargo test -p infra ai::
   ```
3. **Architektur- & Guardrail-Checks:**
   ```bash
   cargo test -p architecture_tests
   ../scripts/add-spdx-headers.sh --check
   ```
4. **Postgres-Integrationstest (sofern Docker läuft):**
   ```bash
   cargo test -p integration-tests --test ai_import_chunk_resume
   ```
