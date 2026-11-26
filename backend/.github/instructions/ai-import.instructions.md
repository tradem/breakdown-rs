---
description: AI import - configuration, concurrency permits, payload storage, GC and restart recovery.
applyTo:
  - "crates/*/src/ai/**"
  - "crates/integration-tests/tests/ai*"
  - "config/default_ai_prompts.toml"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# AI import (`add-ai-script-and-schedule-import`)

#### AI import (`add-ai-script-and-schedule-import`)

- `AI_IMPORT_ENABLED` – enable AI import routes/workers (default: `false`; accepted values: `true`, `1`, `yes`).
- `AI_IMPORT_MAX_CHUNKS_PER_SCRIPT` – maximum script scene chunks per job (default: `128`; bounded to `1..=10000`).
- `AI_IMPORT_MAX_TOKENS_PER_REQ` – maximum output tokens per LLM request (default: `8192`; bounded to `1..=1000000`).
- `AI_IMPORT_MAX_CONCURRENT_JOBS_GLOBAL` – global in-flight job ceiling (default: `16`).
- `AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` – per-user in-flight job ceiling (default: `2`).
- `AI_IMPORT_MAX_DOCUMENT_BYTES` – maximum source document size (default: `20971520`).
- `AI_IMPORT_REQUEST_TIMEOUT_SECS` – provider request timeout (default: `120`).
- `AI_IMPORT_MAX_RETRIES` – **job-level** retries before dead-lettering (default: `5`).
- `AI_IMPORT_MAX_ATTEMPT_RETRIES` – **in-attempt** retries of one chunk's provider call (default: `2`, bounded `0..=10`). Since issue #871 this is a *second* knob: one knob allowed `5 × 5 = 25` paid calls for a single chunk before anything surfaced, each holding a concurrency permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`. `1 + 2 = 3` attempts per chunk is enough to tell a blip from an outage. The analytic worst case of one attempt across **both** nested layers is `(1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs + max_attempt_retries × max(30 s, MAX_IN_ATTEMPT_HINT_SECS)` = **22 min** hosted (`inner = 2`) / **28 min** Ollama (`inner ≤ 3`), because the clients re-request a truncated/malformed answer inside one attempt and, since issue #926, a provider-requested wait can raise each in-attempt pause from 30 s to 120 s (see "Provider retry hints").
- `AI_IMPORT_BREAKER_FAILURE_THRESHOLD` – consecutive retryable provider failures for one `(provider, model)` pair that open the breaker (default: `3`, bounded `1..=10`). Counted per **pair across all jobs, chunks and replicas**. A threshold above `1 + AI_IMPORT_MAX_ATTEMPT_RETRIES` is accepted but logged at startup: the breaker still opens, just more slowly, because one chunk then contributes one failure instead of up to three.
- `AI_IMPORT_BREAKER_ENABLED` – kill switch for the breaker (default: `true`; accepted spellings as `AI_IMPORT_ENABLED`). `false` restores the pre-#871 behaviour exactly.
- `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` – how long one **hold series** may last before the job dead-letters with the provider narrative (default: `21600` = 6 h, bounded `60..=604800`). Measured from the first hold of the series, so a flapping provider cannot reset the budget one probe at a time.
- `AI_IMPORT_PROVIDER_SWEEP_ENABLED` – enable the provider watch (default: `true`).
- `AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS` – provider-watch cadence in seconds (default: `60`, bounded `5..=3600`).
- `AI_IMPORT_LEASE_SECS` – worker claim lease in seconds (default: `900`). An out-of-range number is clamped to `30..=86400`; only absent/unparsable values fall back to the default. A claim records `worker_id` + `lease_expires_at`; once the lease expires another worker may reclaim the `running` job (crash recovery, issue #177). Long jobs keep their claim via a background heartbeat (`LeaseHeartbeat`, renewing at 1/3 of the window), so the lease does not need to cover a whole multi-chunk script run. All worker-originated lifecycle writes (`mark_running`, `mark_succeeded`, `mark_failed`, `record_worker_telemetry`) are **owner-fenced**: a worker whose lease lapsed gets `DomainError::Conflict` instead of overwriting the new owner's state.
- `AI_IMPORT_DEFAULT_PROMPTS_PATH` – optional deployment override documented for prompt packaging; the built-in fallback is `config/default_ai_prompts.toml`.
- `AI_IMPORT_USER_AGENT` – global override for the `User-Agent` sent by every AI provider HTTP client (default: `breakdown-rs-backend/<version> (ai-import)`).
- `AI_IMPORT_USER_AGENT_<PROVIDER>` – per-provider override, e.g. `AI_IMPORT_USER_AGENT_OPENCODE_GO` or `AI_IMPORT_USER_AGENT_OPENCODE` (takes precedence over the global variable). An empty or header-invalid value is ignored and the next source applies.
- `AI_DOCUMENT_PARSER` – document-structure adapter (ADR-041 `D1`, issue #958): `spatial` (default), `docling` or `legacy-pdftotext`. Read **once** at startup; an unknown value fails the boot instead of silently selecting another extraction path.
- `AI_DOCLING_ENDPOINT` – base URL of the `docling-serve` sidecar (e.g. `http://docling:5001/`). Required only when `AI_DOCUMENT_PARSER=docling`; missing or unparsable fails the boot.
- `AI_EVAL_CORPUS_DIR` – **test-only** (not read at runtime): directory of local PDF scripts/schedules for the Golden Corpus harness `cargo test -p infra --test ai_document_eval_corpus`. Unset ⇒ the harness skips; copyrighted broadcast PDFs never enter Git. Set ⇒ the run is **complete**: every document the manifest lists must be present, otherwise the sweep fails (a partial corpus is not a green corpus).
- `AI_EVAL_CORPUS_MANIFEST` – **test-only** override for the expectation manifest, default `backend/config/ai_eval_corpus.tsv`. The manifest is the ONE definition of the corpus (file, kind `script|schedule`, expected scene count, note, `cast=<name>:<category>,…`), so a local run and a CI run assert exactly the same numbers and cast verdicts: only the PDFs are out of tree, the expectations are not. The `cast` column is resolved through the production `resolve_character_category` against that document's parsed `CastDirectory`; a missing name, a wrong category or an emitted uncertainty fails the sweep. Verified against the GDrive fixture folder (issue #961): `292.pdf` 40, `293.pdf` 42, `294.pdf` 43, `Drehbuch_1.pdf` 42, `Drehbuch_2.pdf` 42, `Drehplan_1.pdf` schedule — 20/20 cast assertions.
- **Local corpus run** (from `backend/`, needs `poppler-utils`): `AI_EVAL_CORPUS_DIR=~/Downloads/drive-download cargo test -p infra --test ai_document_eval_corpus -- --nocapture`. The CI runs the **identical** command; only the PDFs come from somewhere else: `crates/integration-tests/tests/ai_gdrive_corpus_materialize.rs` copies `GDRIVE_ROOT` into `AI_EVAL_CORPUS_DIR` (skips without `GDRIVE_CLIENT_ID`, default target `target/eval-corpus`), and the `integration-tests` workflow step "Golden Corpus (GDrive materialise + zone-aware sweep)" runs materialise + sweep together under the same trust gate as the GDrive smoke. Locally the same two commands work with `GDRIVE_*` in the environment, so a developer reproduces CI byte-for-byte.

#### EU vision fallbacks (ADR-041 `D2`, issue #968)

Multimodal schedule extraction may only send page images to a provider whose policy declares
Zero Data Retention, no training on inputs and EU data residency; the gate
(`vision_egress_policy_for_config`) runs before any base64 encoding. Declared providers and their
curated vision models:

| Provider key | Base URL (curated, static) | `/models` catalogue | Policy |
|---|---|---|---|
| `eurouter` | `https://api.eurouter.ai/api/v1` | live feed (`CatalogSource::Eurouter`) | compliant |
| `scaleway` | `https://api.scaleway.ai/v1` | docs-verified (`qwen3.5-397b-a17b`, `mistral-small-3.2-24b-instruct-2506`) | compliant, one accepted exception (ADR-041 `D2.1`) |
| `ovhcloud` | `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1` | live-verified (`qwen3-vl-30b-a3b`, `Mistral-Small-3.2-24B-Instruct-2506`) | compliant |
| `nebius` | `https://api.tokenfactory.nebius.com/v1` | models.dev feed (`Qwen/Qwen3.8-27B`, `deepseek-ai/DeepSeek-V4.1-Flash-1017`) | **fail-closed until `zdr_attested`** (residency caveat: EU retained copy, Global processing region) |
| `ollama` | local | local tags | compliant (zero egress) |

- **Credentials.** There is no provider-specific env var and no per-provider vault path: the API
  key is a SETTINGS credential (`ADR-027`) supplied by the client, and the AI config stores only the
  opaque `vault_key_id`. A blank or malformed reference fails at the vault read
  (`fetch_key`/`settings_id_from_binding_key`), i.e. before the first provider request — never on
  the first page of a paid import.
- **The ZDR attestation.** `AiConfig.zdr_attested` is the operator's confirmation that the provider
  ACCOUNT keeps no data. It is collected in the client's AI-config screen and persisted with the
  config together with the key reference (never inside the vault: the vault holds secrets only).
  It lifts exactly the retention flag of a provider whose ZDR is an account switch (`nebius`); it
  can never lift the no-training/EU-residency requirements. **It is bound to the credential it was
  given for:** an update that changes `vault_key_id` (or the provider) clears a stored `true`
  unless the same request re-asserts it, because the replacement account's `ZDR Mode` is not
  observable. Runbook: `docs/operations/runbooks.md` §"AI import vision egress"; the accepted
  provider caveats: ADR-041 `D2.1` → "Accepted exceptions under D2".
- **Pricing.** `ai_model_pricing` carries `curated_seed` rows for every curated fallback model
  (migration `20261125000002`), so `#675`/`#794` cost snapshots price the page calls. A model
  without a row stays honest absence (`CostStatus` unknown), never a zero-cost snapshot.
- **Re-verification.** The policy and the catalogue are live data: a new provider or model needs
  the verification date plus its source link in ADR-041 `D2.1`, and only IDs that appear in the
  provider's own catalogue may be curated. `nebius` `/v1/models` requires a paid key, so that check
  is a deployment task in the runbook.

#### Nightly vision smoke (ADR-041 `D2`, issue #974)

`ai_llm_smoke_test` carries the live page-image coverage: `vision_smoke_catalog_preflight` (zero
tokens) and `vision_smoke_reads_a_schedule_page` (one page of `Drehplan_1.pdf`, ≈ $0.001 per
provider). Both run in `AI Import Nightly`; the register:

| Variable | Kind | Default | Meaning |
|---|---|---|---|
| `AI_VISION_REQUIRED_PROVIDERS` | `vars`, comma-separated | `ovhcloud` | must-pass rows — a failure is **red** |
| `AI_VISION_ADVISORY_PROVIDERS` | `vars`, comma-separated | `scaleway` | advisory rows — a failure is one `vision-smoke advisory-degraded provider=… code=…` WARN line |
| `AI_VISION_SMOKE_PAGE` | `vars` | `2` | 1-based page to render (page 1 is the `ROLLEN` legend) |
| `AI_VISION_KEY_<PROVIDER>` | `secret` | — | per-provider credential, upper-cased [`LlmProvider::as_str`] with `-` → `_` (the `AI_IMPORT_USER_AGENT_<PROVIDER>` convention); `AI_VISION_KEY_EUROUTER` falls back to `AI_LLM_API_KEY` **only** when `AI_LLM_PROVIDER=eurouter` |

Rules that come with it:

- **Required vs advisory (`D3`).** A missing credential ⇒ SKIP + WARN naming the variable (never a
  silent green). A required failure ⇒ red. An advisory failure ⇒ one greppable WARN line so a trend
  is visible without a provider flap turning the board red. A provider listed under both is
  **required**.
- **No paid EURouter vision call (`D2`).** `eurouter` is a reseller fronting many upstreams, so a red
  night there is ambiguous (our extractor vs. their outage). It gets the free authenticated
  `GET {base}/key` read (`ProbeCapability::KeyEndpoint`, via the production
  `KeyEndpointAccountProbe`) and is never listed as a vision provider.
- **`nebius` stays out of the matrix.** Its ZDR is an account switch, so
  `vision_egress_policy_for_config(nebius, false)` is deliberately non-compliant; the smoke asserts
  in-process that an unattested page is refused, so listing it would assert a gate breach.
- **The canary is the most stable endpoint, not the production one (`D1`).** Production fidelity is
  the text pass's job (`AI_LLM_*`, unchanged). Do not "align" `AI_VISION_*` with `AI_LLM_*`.
- **Zero-token preflight (`D4`).** `ovhcloud`'s `/v1/models` answers anonymously and its curated IDs
  are asserted there; a rotated ID is red before any money is spent. The read stays **anonymous even
  when the credential is set** (`catalogue_reads_anonymously`): an authenticated read of that endpoint
  answers `401` for a token without the AI-Endpoints action, so attaching the key would turn a free
  catalogue check into a credential verdict the paid step already delivers. Every read uses
  `CuratedProviderUrls::base_url` through `build_hosted_client` — never a user-supplied URL.
- **Cost reporting is a `const` table in the test** (`VISION_RATE_CARDS`, verified 2026-11-25; the
  Scaleway figures are its EUR list price). No DB read, no new pricing subsystem; an unpriced model
  prints `cost_usd=unknown`, never `0.0`.
- Switching provider / rotating a model: `docs/operations/runbooks.md` §"AI import vision egress" →
  "Nightly canary".

> **Descriptive `User-Agent` (issue #521).** The curated opencode / OpenCode-Go
> gateways triage requests on `User-Agent`; a blank, generic or reqwest-default
> agent (`reqwest/<version>`) is answered with `403`. Every provider client
> (catalog, Ollama, hosted chat) therefore sends the configured descriptive
> agent — additive transport metadata that leaves the issue #170 redirect /
> DNS-pin / no-proxy policy untouched. A `User-Agent` is not a credential.
>
> **Verify before attributing a `403`.** The same research note also links a
> `403` to model entitlement. When a real opencode-* call fails, capture the
> response body `code` and distinguish UA-triage from entitlement before
> changing the agent; do not commit to a one-cause fix without evidence.

> **Concurrency permits are cancellation-safe (issue #178).** The two
> `AI_IMPORT_MAX_CONCURRENT_JOBS_*` ceilings above are enforced by one owned
> row per permit in `ai_import.concurrency_permit`, not by an anonymous
> counter. `Drop` cannot `.await`, so a worker cancelled during shutdown could
> never run `release()`; recovery therefore lives in the permit itself. A
> permit's `Drop` hands its id to the in-process reclaimer task
> (`PgAiConcurrencyLimiter::spawn_reclaimer` — the fast path), and every row
> carries an `expires_at` lease that the next acquisition sweeps, so even a
> process kill self-heals within one lease window. Long holders renew via
> `PgAiConcurrencyPermit::renew` at `permit_renewal_interval` (1/3 of the
> window). All release paths are `DELETE ... WHERE id = $1`, so double-release
> is impossible.
>
> **The reclaim is bounded per permit (issue #528 follow-up).** A permit whose
> acquisition was cancelled mid-`commit` can still have its row locked by that
> transaction, so the reclaimer's delete is executed in a short transaction with
> `set_config('lock_timeout', …, true)` (`RECLAIM_LOCK_TIMEOUT`, 200 ms) and
> retried up to `RECLAIM_ATTEMPTS` (4) times with a linear backoff
> (`RECLAIM_BACKOFF_BASE`, 100 ms × attempt). Without the bound, one stuck row
> blocked the single reclaim loop head-of-line and delayed every later permit;
> without the retry, a single transient failure demoted the fast path to the
> lease floor (30 s). `reclaim_retry_budget()` is the analytic worst case per
> permit and is what integration tests budget against — never a guessed sleep.
> Only after the budget is exhausted is the row left to the lease.
>
> `AiWorkerRuntime::run_job` renews the permit while the operation runs, so a
> multi-hour script job cannot have its capacity swept out from under it (that
> would over-admit past the ceiling); a `Conflict` aborts the job rather than
> letting it run on capacity someone else now owns.
>
> **Composition-root wiring:** call `spawn_reclaimer()` and keep the returned
> `PermitReclaimer` alive for the process lifetime. Graceful shutdown has a
> required order, because every sender clone must be gone before the channel
> closes and permits hold one too: (1) cancel **and join** every task that may
> hold a permit, (2) drop every clone of the limiter, (3) await
> `PermitReclaimer::shutdown()`. Skipping a step leaves a live sender and the
> await hangs; dropping the handle instead aborts the task and silently
> downgrades those reclaims to lease-only — exactly the 900s capacity outage
> this design removes. Use `abort()` when the ordering cannot be guaranteed.

#### Document-structure extraction (ADR-041 `D1`/`D7`, issue #958)

The import workers do not read PDFs themselves. Both are generic over the
`DocumentStructureExtractor` port (`ScriptImportWorker<Q, C, E = LegacyPdfToTextAdapter>`,
`ScheduleImportWorker<Q, C, E>`), which returns the canonical
`core::ai::document::StructuredDocument` IR — 1-based pages, reading-order blocks,
normalized `0.0..=1.0` geometry, preserved `<table>` markup — instead of one flat
`String`. Segmentation is **zone-aware** since issue #959: `ScriptImportWorker::process`
hands the IR to `core::ai::extract_scenes_from_structured`, which classifies every
page (`classify_document_zones`) and emits `SceneChunk`s from `ScriptBody` prose
only. `flattened_text()` survives as the *flat-text seam*
(`SegmentedScript::from_flat_text`, used by `process_text` and the string-level
unit tests): for `legacy-pdftotext` it is byte-identical to the old
`pdftotext -layout` output, while `spatial`/`docling` join the blocks *their*
parser produced, so their flattened view differs in text and boundaries by design.

- **Selection happens exactly once**, in `crates/api/src/main.rs`:
  `ConfiguredDocumentExtractor::from_env(&bounds)` → `WorkerDeps.extractor` (by
  **value**). Never introduce `Arc<dyn DocumentStructureExtractor>`,
  `Arc<ConfiguredDocumentExtractor>`, `Arc<SpatialPdfExtractor>`,
  `Arc<LegacyPdfToTextAdapter>` or `Arc<reqwest::Client>`: `Spatial`/`Legacy` are `Copy`
  two-word configs and `reqwest::Client`/`PgPool` are already internal `Arc`s.
- **Adapters:** `spatial` (`poppler-spatial-v1`, `pdftotext -bbox-layout` + on-demand
  `pdftocairo` page renders), `docling` (`docling-http-v1`, `docling-serve` HTML with
  `colspan`/`rowspan`), `legacy-pdftotext` (`legacy-pdftotext-v1`, flat text, the
  rollback target — it refuses `render_page` by name).
- **The IR carries no page images.** `render_page(bytes, page_number, RenderOptions)`
  renders one page on demand (bounded by `RenderOptions::max_bytes` and the adapter
  timeout) so a page-streaming caller keeps one page's PNG, not a document's worth
  (ADR-041 `D1`; the document-wide ceiling belongs to the page-streaming loop in
  issue #960).
- **`parser_fingerprint` is fingerprint, not decoration.** It enters
  `chunk_store::fingerprint_key` next to `CHUNKER_VERSION`, so switching
  `AI_DOCUMENT_PARSER` deletes the stored chunk prefix and restarts at chunk `0`
  instead of splicing chunks cut by two different parsers. Changing what an adapter
  *emits* therefore requires bumping its fingerprint — otherwise a stored prefix
  silently resumes under the old algorithm.
- **Every subprocess goes through `ai::subprocess::run_bounded`**: stdin/stdout
  streaming, `max_output_bytes + 1` read limit, `tokio::time::timeout`, and
  kill-and-**reap** on every error/timeout branch. Do not spawn `pdftotext`/
  `pdftocairo` directly anywhere else — a leaked child is exactly what that helper
  exists to prevent. `pdftocairo` (not `pdftoppm`) renders page PNGs: `pdftoppm`
  cannot stream to stdout and would need a temporary file path.
- **Verification:** always-on synthetic fixtures in
  `crates/core/src/ai/document_tests.rs` and
  `crates/infra/src/ai/spatial_pdf_tests.rs`; the out-of-tree corpus harness runs
  only with `AI_EVAL_CORPUS_DIR` set and reads its expectations from
  `config/ai_eval_corpus.tsv`.

#### Zone-aware segmentation (ADR-041 `D3`/`D4`/`D7`, issue #959)

A broadcast screenplay is not one text: cover page, cast directory, a two-page
`"SCRIPT REPORT"` index, five pages of `"SYNOPSIS"` prose, and only then the
script. Scanning that flat string from line 1 glued the synopsis onto the last
index entry — the model then invented scenes and dumped episode-wide characters
into the final one. Pass 0 fixes this before a single token is spent:

- **`core::ai::document::classify_document_zones(document, is_scene_heading)`**
  labels every page `TitlePage | CastList | SceneIndex | FrontMatter | ScriptBody`.
  Banners (`"SCRIPT REPORT"`, `"PERSONEN/ HAUPTCAST"`, `"SYNOPSIS"`,
  `"MEDIZINISCHE FÄLLE"`), heading/dialogue counts and the header/footer bands
  decide it; the caller **injects** the heading detector so zoning and chunking
  cannot disagree. A page with no scene signal *after* the body started stays
  `ScriptBody` (a scene running over a page break must not be dropped), and a
  document with **no** `ScriptBody` page widens to "all prose" instead of
  failing the import — that flag (`fell_back_to_script_body`) is the signal the
  VLM structural pass of issue #960 is meant to answer.
- **`zoned_lines` / `LineRole`** exclude `PageHeader`, `PageFooter` and
  `"<N> CONTINUED:"` / `"FORTSETZUNG"` banners (`is_continuation_marker`) from
  chunk text. Chunk text is sliced **verbatim** from the block text — never
  re-transcribed by a model, because `verify_draft_outfits` validates
  `source_quote` substrings against exactly those bytes.
- **`StructuralPlan`** is the accepted plan (page zones + the block anchors cut
  at) with a canonical rendering; `chunk_store::structural_plan_digest` hashes it
  into `ExtractionFingerprint::structural_plan_digest`, so a retry that accepts a
  different plan restarts at chunk `0` instead of splicing two plans.
- **`SceneIndex` reconciliation** compares the index labels with the body labels
  and emits a targeted `scene_number` `FieldAmbiguity` on a mismatch — never a
  cross-zone text merge.
- **`CHUNKER_VERSION` is `2`.** Bump it again whenever the segmentation changes
  what a chunk *is*, and remember that a change to the zone rules changes the
  plan for every document (the digest handles that, the version handles the
  chunking).

#### Cast directory & deterministic categories (ADR-041 `D4`, issue #961)

The front-matter cast sheet is parsed once per extraction into a plain owned
`core::ai::CastDirectory` (`document::parse_cast_directory` over `CastList`
lines; the flat-text seam uses `parse_cast_directory_from_text`). Section
headers map through the `'static` `CAST_SECTION_MAPPING` slice — no `HashMap`,
`LazyLock` or `Arc`. Trailing `(44)` / `(8, OT)` / `(MT)` parentheticals are
stripped from `canonical_name` / `normalized_identity`; `inline_ot` records the
fact but never outranks the declared section. `SegmentedScript.cast_directory`
is borrowed by every chunk.

- **Role ladder:** `preview::resolve_character_category` returns the declared
  `CastDirectory` category first (unconditionally, including a listed
  `"Jonas Weber (8, OT)"` → `guest`), then a season `Character` category, then
  a strict inline background marker (`(OT)` / `(O.T.)` / `Off-Text` /
  `Statist` / `Komparse` → `extra`), then a zero-dialogue generic role, then
  `main_cast`. Exactly one `characters` uncertainty is added for a genuine
  two-section conflict; a missing signal and a marker are never doubts. The
  worker overwrites the model's category AFTER each chunk — the prompt is
  context, never the authority (zero hedging, zero `(OT)` → `guest` promotions).
- **Season cast boundary:** `WorkerDeps.character_repo` is
  `CharacterRepositoryImpl` **by value** (its `PgPool` is already an internal
  `Arc`). `script_worker_tick` calls `list_by_season` once for
  `job.target.season_id`, bounded and best-effort; a miss, an error or a missing
  target becomes an empty slice. No repository call in an adapter, saga or
  aggregate (`AGENTS.md` §1).
- **Kerning:** `document::normalize_kerning` joins whitespace-split runs only
  when they match a multi-character name in the same `CastDirectory` (`"Mik k
  o"` → `"Mikko"`); ordinary prose is untouched. The model sees the normalized
  view inside a trailing `<document-context>` block, while
  `verify_draft_outfits_with_normalized` accepts a `source_quote` against the
  raw AND the normalized scene text.
- **Continuity:** `neighbor_brackets` derives `previous_scene` / `next_scene`
  (number, location, mood, script day, `same_script_day`) from ordered chunks;
  Pass 1 renders them with the cast summary, Pass 2 adds the same pair to the
  `continuity_state` decision payload. A model split of one chunk gives every
  resulting preview row the same bracket.

#### Page-streaming multimodal schedule extraction (ADR-041 `D2`/`D5`, issue #960)

A spatial PDF schedule is not one text blob: 8+ iText pages of borderless
multi-row grids, a two-column `"ROLLEN"` legend on page 1, full-width
shooting-day banners, `"Drehfrei"` rest days, and pick-up suffixes
(`"300.37N"`). `ScheduleImportWorker::process` therefore streams PDFs
PAGE BY PAGE (`extract_pdf_pages`):

- **Vision seam:** `LlmClient::chat_vision_constrained` /
  `extract_schedule_page` (core `ports`). The hosted transport's
  pre-egress gate (`vision_egress_compliant(vision_egress_policy(provider))`,
  ADR-041 `D2`) runs BEFORE any base64 encoding or HTTP call — fail-closed for
  every provider that has not declared ZDR + no-training + EU residency; only
  `EURouter` is declared, local `Ollama` needs no gate (zero external egress)
  and rides the PNG in its `images` array. One bounded plain-JSON fallback
  covers providers that reject `image_url` + strict `json_schema` bodies.
- **Carry-over:** a stack-owned `ScheduleCarryOver` (day label, date, legend)
  is borrowed by every page call and moved into `ShootingSchedule.cast_legend`
  at the end — no `Arc`, no map cloning. `"Drehfrei"` banners never emit rows
  and never overwrite the active day; a bottom-of-page banner travels to the
  next page via `end_of_page_shooting_day_label`.
- **Bounds & telemetry:** the document-wide rendered-byte ceiling
  (`AI_IMPORT_MAX_RENDERED_TOTAL_BYTES`, default 64 MiB, clamped to 512 MiB)
  aborts the job instead of accumulating `K` images; each page PNG is dropped
  before the next render; usage accumulates across ALL page calls so the
  `#675`/`#794` cost snapshot covers an 8-page schedule exactly; progress
  frames publish `chunk = page_idx`, `chunks_total = page_count` (`#664`).
- **Rollback:** the loop engages only when
  `parser_fingerprint != legacy-pdftotext-v1` — with
  `AI_DOCUMENT_PARSER=legacy-pdftotext` the pre-#960 single flat-text request
  runs unchanged.
- **Wire metadata (additive, all `#[serde(default)]`):** `cast_legend`
  (`ScheduleLegendEntry` with `ScheduleRoleModifier`
  `none`/`dummy`/`voice_only`/`extra_ot`; truncated cells like `"(Dummy"` and
  `"(Nur Stimme"` classify), `shot_suffix` (`"300.37N"` → `Some("N")`;
  `"SB7.2"`/`"T3"` stay `(None, None)` and land in `unmatched_schedule_rows`),
  `cast_refs` (codes resolved against `cast_legend`; unknown codes are dropped
  silently). `ScheduleApplyWorker` dispatches ZERO `CharacterCommands` (`D6`).
- **Footer-band note:** schedule grids carry REAL rows in the bottom band
  (an iText export's page number lives in the TOP band), so the schedule page
  extractor strips only the header band — a footer-band filter drops the last
  rows of every page (found on `Drehplan_1.pdf`: day-6/11 banners and scene
  `300.16` sit below `y = 0.91`).
- **Verification:** the Golden Corpus harness asserts the schedule through the
  same deterministic `extract_schedule_from_structured` the worker feeds via
  `sched=` expectations in `config/ai_eval_corpus.tsv` (row floor, distinct
  day count, day-1 date, `300.37N`, `SB7.2`/`T3`, legend modifiers,
  zero-`"Drehfrei"`). Run it exactly like the script sweep with
  `AI_EVAL_CORPUS_DIR` set.

#### AI payload storage (durable source/preview blobs)

All three variables (`AI_PAYLOAD_S3_ENDPOINT`, `AI_PAYLOAD_S3_ACCESS_KEY`, `AI_PAYLOAD_S3_SECRET_KEY`) must be set to enable durable S3 storage for AI import payloads.

- `AI_PAYLOAD_S3_ENDPOINT` – S3 API endpoint for AI import payloads (e.g. `http://garage:3900`).
- `AI_PAYLOAD_S3_ACCESS_KEY` – S3 access key for AI payload storage.
- `AI_PAYLOAD_S3_SECRET_KEY` – S3 secret key for AI payload storage.
- `AI_PAYLOAD_S3_BUCKET` – S3 bucket name for AI payloads (default: `ai-import-payloads`).
- `AI_PAYLOAD_S3_TLS_ROOT_CERT` – optional PEM path of the pinned root CA for `https://` S3 endpoints.

> **Durable storage**: When all three required variables are set, AI import payloads survive API
> restarts. Pending jobs can resume, retries can reload source documents, and succeeded jobs
> continue serving previews.
>
> When `AI_IMPORT_ENABLED` is false, missing S3 variables are acceptable — the API wires
> `infra::ai::UnconfiguredAiPayloadStore`, which refuses every payload operation with
> `503` (never in-memory storage, which would accept payloads and drop them on restart;
> issue #181). When `AI_IMPORT_ENABLED` is true, all three S3 variables must be set or the
> API **fails to start** to prevent silent data loss.

> **Boot sequence**: Garage must be up and provisioned (bucket + access key) before the API
> starts. In dev, `./scripts/enable-dev-ai-import.sh` (issue #428) boots the AI overlay
> (`docker-compose.dev.ai.yml`), provisions the buckets/key and writes `.env.dev-ai.local` for the
> host-run API; the base dev Garage stays internal-only without the overlay. During first
> rollout set `PHOTO_GC_DRY_RUN=true` to observe orphan detection logs before enabling deletion.

#### AI payload GC (periodic cleanup)

- `AI_PAYLOAD_GC_ENABLED` – enable periodic cleanup (default: `true`).
- `AI_PAYLOAD_GC_INTERVAL_SECS` – sweep interval in seconds (default: `3600`).
- `AI_PAYLOAD_GC_MAX_AGE_SECS` – only cleanup payloads for jobs older than this (default: `604800` = 7 days).
- `AI_PAYLOAD_GC_BATCH_SIZE` – max terminal-state jobs per run (default: `1000`).
- `AI_PAYLOAD_GC_DRY_RUN` – log-only mode (default: `false`; set `true` for first rollout).

> **AI payload GC**: A periodic worker cleans up Garage payloads for terminal-state jobs
> after the configurable grace period. The worker uses a Postgres advisory lock to prevent
> concurrent sweeps. Set `AI_PAYLOAD_GC_DRY_RUN=true` for the first rollout to observe
> deletion logs before enabling actual cleanup.
>
> **Terminal means unclaimable (issue #181).** The sweep covers exactly
> `succeeded`, `dead_letter` and `payload_unavailable`. `failed` is **never**
> swept — it is the *retryable* backoff state, and sweeping it deleted the source
> document of jobs that were still scheduled to run.
>
> Do not "refine" this to sweep `failed` once `retries >= max_retries`. The claim
> predicates match `status = 'failed' AND (next_attempt_at IS NULL OR
> next_attempt_at <= now())` and **never consult `retries`**, so an exhausted
> `failed` row is still handed to the next worker. Nothing leaks as a result:
> `mark_failed` dead-letters a job in the same statement that exhausts its budget,
> so a `failed` row is by construction one that still has a future.
>
> **The sweep is stateful (issue #206).** Each deleted payload is recorded in
> `ai_import.ai_payload_cleanup`, keyed `(job_id, payload_kind)`, and the sweep
> anti-joins those marks so a job is selected only while it still owes a
> payload. Without the marks the oldest `batch_size` jobs were re-selected on
> every run forever: deletions are idempotent so nothing broke, but the S3
> round-trips were re-paid, the run-history counters re-counted the same
> deletions, and any job behind the `LIMIT` never got swept at all — retention
> silently stopped being enforced. The `LIMIT` is a rate limit, not a horizon.
>
> **Only real deletions may be marked.** A mark hides the payload from every
> future sweep, so it must never outrun the deletion:
> - deleted → marked;
> - **not found → marked** (the goal state holds, and a terminal job can never
>   be re-claimed to recreate the payload, so re-probing it is pure waste);
> - failed → **not** marked, so the next sweep retries it;
> - dry run → **not** marked, or observation mode would permanently hide the
>   very objects it was meant to report.
>
> Marks are flushed *before* the run-history row and *before* the early return
> on the first deletion error, so one failure cannot discard the marks its
> siblings in the batch earned. A sweep must never touch `updated_at` on the
> job row — that column is both the retention clock and the sweep's `ORDER BY`
> key, so writing it there would reset the window it measures.

#### AI import restart recovery (issue #181)

AI import payloads live in Garage (`AI_PAYLOAD_S3_*`), so a process restart does not
lose them. Behaviour per job status after a restart:

| Status | Behaviour |
|---|---|
| `pending` | Runnable; the next worker claims it and loads the source from durable storage. |
| `running` | Its worker is gone; the claim lease expires and another worker reclaims it, releasing the orphaned permit. |
| `failed` | Runnable once `next_attempt_at` is due — the claim predicate ignores `retries`. Payloads are **never** GC'd. |
| `dead_letter` | Terminal; payloads GC-eligible after retention. `mark_failed` lands a budget-exhausted job here directly. |
| `succeeded` | Preview served from durable storage; apply reloads it. GC-eligible after retention. |
| `payload_unavailable` | Terminal and **non-resumable**: never claimed, never retried. |

A worker that cannot load a payload because it is **absent** (`DomainError::NotFound`)
calls `AiImportQueue::mark_payload_unavailable`, which moves the job to
`payload_unavailable` immediately, bypassing the remaining retry budget — every retry
could only re-discover the same absence while consuming a claim and a concurrency
permit. A worker that cannot load it because storage is **unreachable**
(`ServiceUnavailable`) still fails retryably: that is transient, and the bytes may well
still be there. Never collapse these two cases.

The composition root must never hold an in-memory payload store: with AI import
disabled, `main.rs` wires `infra::ai::UnconfiguredAiPayloadStore`, which refuses every
operation with `ServiceUnavailable` (deliberately not `NotFound`, which would
dead-letter jobs). `MemoryAiPreviewStore` is test-only.

#### AI provider circuit breaker (issue #871)

Two nested retry layers exist and must not be confused:
**in-attempt** (`AI_IMPORT_MAX_ATTEMPT_RETRIES`, per chunk) and **job-level**
(`AI_IMPORT_MAX_RETRIES`, per job). They used to be one knob, which is how one
chunk could cost 25 paid calls.

A **durable** breaker per `(provider, model)` pair sits in front of both:

- **Only `closed` admits a claim.** The filter is one `NOT EXISTS` predicate on
  all four claim paths (`claim_next`, `claim_next_kind` and their reconciling
  variants). `retry_at` is deliberately **not** part of it: it is the probe
  schedule, not a claim gate — filtering on it would lift the filter the instant
  a probe became due and drain the queue instead of running one probe.
- **Only retryable provider failures count.** A revoked key, a bad model or an
  entitlement 4xx is `dependency.auth-failed`-class permanent (#637) and must
  never open a breaker: that would convert one user's misconfiguration into an
  outage for everyone on the endpoint.
- **A held job is `failed` with `retries` unchanged and one attempt row per hold
  *series* (issue #942 W2).** The wire carries an additive `provider_hold`
  (`provider`, `model`, `reason_code`, `state`, `until`, `hold_deadline`,
  `chunks_done`); `last_error` keeps #822's narrative so an older client still
  renders. `provider_hold` is cleared by every other lifecycle write, with
  exactly one exception: the hold-expiry write keeps it with `state = expired`,
  because that marker is the only durable signal separating an expiry from a
  spent retry budget.
  Do not "restore" the pre-#942 rule of appending **no** attempt row: it made the
  most common real provider state (repeated failures → hold) the one state with
  zero diagnosable evidence — `last_error` held a bare problem code and the
  attempt history stayed empty, so a client-timeout hold, an HTTP-status hold and
  a bounded-body hold were indistinguishable from Postgres alone. The row is
  written by the **first** hold of a series (`provider_hold_series_started_at`
  was NULL before it), carries the bounded failure narrative in `error_summary`
  and the fired registered code in `error_code`, and is `retryable = TRUE`
  (a hold resumes; a dead letter does not). "First of the series" is read under the
  row's `FOR UPDATE` lock in its **own** statement: a same-statement `before` CTE
  cannot see a pre-update value (the transaction's own `held` UPDATE is already
  visible to it), so it silently answered "not first" and wrote no row at all.
  A re-hold inside the same series
  appends nothing, and `retries` stays untouched on every path. The sweeper's
  `hold_runnable_jobs` path (a job enqueued while the breaker was already open)
  writes no row — it has no first-hand failure — so a held job may legitimately
  have none. `error_summary` is bounded twice (the classifier's 400-char detail
  and `LEFT(…, 1000)` in the insert), because `mark_held` is a public port method
  and the SQL must be safe on its own.
- **`attempt_no` is not unique per job; both history readers break the tie
  chronologically.** A hold numbers its row `retries + 1` without charging a retry,
  so the next `mark_failed` reuses that number. Ordering by `attempt_no` alone let
  the history `LIMIT` drop the newer evidence and mis-order the tied pair, so
  `list_attempts` and the jobs-list `newest_attempts` window order by
  `attempt_no DESC, created_at DESC, id DESC`.
- **Recovery is a two-stage probe, never elapsed time, and a probe never closes
  (issue #942 W1).** "Elapsed ⇒ closed" would resume paying into a still-broken
  endpoint. The preflight is **capability-accurate** (`probe_capability`,
  `core::ai::ports`), because the former `GET {base}/models` read was blindness
  in two directions: EURouter serves it *publicly* (`200` in 0.2 s for a bogus
  bearer token, so a dead key looked healthy), and a healthy account does not
  prove a healthy `(provider, model)` chat path (`GET /key` `200` while
  `POST /chat/completions` stalled at 120 s — `flap_count` reached 3 in 30 min).
  - `KeyEndpoint` (`eurouter`, `openrouter`): authenticated `GET {base}/key`,
    zero tokens. `200` with positive/absent `limit_remaining` ⇒ **usable**;
    `200` with `limit_remaining <= 0`, `401`/`402`/`403`, any other status,
    transport error or timeout ⇒ **not usable** (the breaker stays `open`).
  - `LocalTags` (`ollama`): unauthenticated `GET {base}/api/tags`, unchanged —
    the hosted deadline-bearing client would leak a token onto a plain-HTTP
    curated origin (CWE-319).
  - `NoPreflight` (the other five): **no** synthetic metadata probe. The elapsed
    window itself grants the single trial; a `200` from any public endpoint must
    never be treated as proof of usability.
  - A usable preflight moves `open → half_open` and grants **one** trial token
    (`provider_health.trial_job_id`), never `closed`. `closed` happens only when
    a real **paid call** answers (`record_success`), which also releases the
    pair's held jobs.
  - While `half_open`, the claim predicate admits exactly the token holder
    (`ph.trial_job_id = job.id`); every other job of the pair stays held. That
    fence is SQL-only for a reason: the in-process gates never see a job id, so
    they admit `half_open` and rely on the claim predicate to name the one job.
  - A trial run uses **0** in-attempt retries (`ProviderGate::attempt_retries`),
    so a broken model costs `1 × request_timeout` per window instead of
    `(1 + AI_IMPORT_MAX_ATTEMPT_RETRIES) ×`. A retryable trial failure re-opens
    the breaker **immediately with `flap_count + 1`** (a paid call failing right
    after a passing preflight is a new incident, not the same outage), which is
    what makes the window escalate instead of oscillating. Trial ownership is
    decided **per paid call**, not per attempt: a chunk loop re-reads it before
    each chunk, so the chunks after the one that closed the breaker get the
    ordinary retry budget back instead of running un-retried on a stale flag.
  - A trial consumed by a **terminal** failure (revoked key, exhausted quota)
    releases the holder **in the same statement that ends the job** (`mark_failed`
    / `mark_payload_unavailable`, fenced on the failing job's id) and leaves
    `half_open` with no holder; the sweeper then grants the next single trial when
    the window elapses (`begin_provider_trial`). Releasing the token touches no
    counter and no `retry_at`, so the pair still costs at most one paid call per
    window. Without that release the pair stayed `half_open` holding a token that
    named a dead job — and since a grant requires `trial_job_id IS NULL`, no other
    held job of the pair could ever run a trial again. The probe never retires or
    terminalizes a job.
  - **A grant needs "no holder" AND "no outstanding probe lease".** `half_open`
    with no holder has two meanings and only one is grantable: a finished probe
    (lease released — grant now) and a probe in flight (lease held — leave the
    transition to it, or its own fenced result clears the token it would stamp and
    grants a second trial in the same window). A **stale** lease is not grantable
    either: the recovery for a hung prober is the takeover branch of
    `try_begin_probe` (`open_breakers.probe_started_at` + `probe_lease_is_live` is
    what lets `run_probes` tell those three apart).
  - **A held-row refresh never delays the trial holder.** `refresh_held_jobs`
    excludes the job named by `trial_job_id`: the grant and the refresh happen in
    the same sweep tick, and re-pointing the holder at `now + min_open(…)` meant
    the trial it had just been granted could not be claimed until the next window.
- **The probe is a task, not a claimed job.** Only `closed` admits a claim, so no
  worker runs for the pair when the probe is due. It runs as lease CAS → request
  **outside any transaction** → fenced result, so a hung probe cannot hold the
  row lock and lock out the takeover its own lease exists to allow.
- **Mid-run abort happens at the chunk boundary.** The in-flight request is not
  aborted (an aborted HTTP request is not refunded), so the overspend bound is
  exactly one chunk per worker.
- **Quota exhaustion has its own code (issue #942 W3).** An upstream
  `402 Payment Required` (EURouter's budget/spend cap) and a `429` whose body
  matches the provider's quota markers both produce
  `DomainError::LlmProviderQuotaExhausted` → `ai-import.provider-quota-exhausted`
  (402), superseding #822 D-X1 / #927's reuse of
  `ai-import.llm-provider-unavailable`. The split is presentation-only: the
  variant stays `is_retryable() == false`, so it dead-letters immediately, and
  `retry_bounded` still refuses to count it toward the breaker — an empty account
  must never open the deployment-wide `(provider, model)` breaker for other
  users (#927's invariant, pinned by
  `provider_gate_tests::a_quota_exhausted_provider_failure_is_terminal_*`).
- **Operability:** the durable row plus the `#871 provider breaker` log marker;
  see `docs/operations/runbooks.md` §16. `GET /v1/health` gains **no** provider
  check (unauthenticated, 2 s timeout, no credential).
- **`GET /v1/ai-import/providers/{provider}/health?model=` is the user-facing
  read of the same facts (issue #942 W4), and it is a DIFFERENT read from the
  probe above — do not merge them.**
  - **The credential is the caller's own**, resolved from *their* `AiConfig`
    rows (`vault_key_id` / `decision_vault_key_id`) →
    `settings_id_from_binding_key` → an ownership check against *their* settings
    binding → the Vault read. The background probe's `donor_jobs` credentials
    are confined to its fleet-wide verdict and must **never** populate this
    response (that would publish another account's verdict and balance). A
    missing, foreign or unreadable binding degrades to
    `credential_configured: false`, never to `404`/`500` and never to an
    existence oracle.
  - **`(provider, model)`-shaped, never a single provider verdict:**
    `ai_import.provider_health` is keyed by the pair. The response carries the
    requested pair, else the caller's configured models, plus every non-`closed`
    row of the provider (an outage that holds the fleet is what a user needs to
    see before starting an import, and a row carries no tenant data).
  - **`trial_job_id` never crosses the wire.** It names a job that may belong to
    another user, so the DTO exposes `trial_granted: bool` instead.
  - **Three-valued budget, never a fabricated `0`:** absent `budget` = the
    provider reports no budget read (or there is no credential to read it with);
    `budget.remaining: null` = the provider answered and reports **no limit**; a
    number = a real figure (including a measured `0`).
  - **`unknown` is a first-class verdict.** No verified endpoint, a transport
    failure or a timeout answers `probe_status: unknown` — never `not_usable`
    (that would render an unmeasured state as a denial, `frontend-flutter`
    AGENTS §1/#816). The *breaker* mapping is the opposite direction and stays
    as it was: `Unknown ⇒ NotUsable` for the paid-call gate, so no money is
    spent on an unknown.
  - **The cache key is `(user_id, provider, vault_key_id)`** with a 60 s TTL
    (`CachedAccountProbe`). Keying by provider alone would serve one user's
    balance to another; including the Vault reference makes a key rotation a
    miss instead of a stale number.
  - **AUTHZ-GATE:** `authorize_credential_role` inside the handler (ADR-027; no
    new `*_in_season` predicate, ADR-035 B2), and `GET /v1/ai-import/configs`
    stays pure Postgres — the health route is the only one that may leave the
    process.

#### Chunk-level resume (issue #871, workstream B)

A retried attempt continues at the first chunk that never completed instead of
re-extracting from chunk 0. The issue's evidence is a 42-chunk document that died
at chunk 25 **three times**: the same ~25 chunks paid for three times.

- **The store.** `ai_import.ai_import_job_chunk` holds one row per completed chunk
  — the parsed `ScriptContext`-shaped result plus that call's usage. The stored
  unit is the **paid call**, which is the only unit that matters for cost. A
  table rather than a JSONB column because one bounded insert per chunk beats
  O(n²) bytes, and because `ai_import_job.updated_at` is load-bearing (retention
  clock, GC `ORDER BY`, ETA anchor) and must not be written once per chunk.
- **The cursor is derived, never stored**: the length of the contiguous stored
  prefix. `MAX(chunk_index) + 1` over `0, 1, 3` would answer 4 and quietly omit
  chunk 2 from the preview; a stored cursor can disagree with the rows after a
  lost write. A row beyond a hole is unreachable (the merge is a prefix walk), so
  it is deleted with `#871 chunk resume hole at <index>`.
- **Every chunk write is fenced by a row LOCK, not a predicate.** Under READ
  COMMITTED a bare `INSERT … SELECT … WHERE status = 'running' AND worker_id = $2`
  reads the job row without a lock, so another session can reclaim the job and
  rewrite `extraction_key` between the read and the commit — and the stale write
  lands anyway. `SELECT … FOR UPDATE` on the job row, and the invalidation path
  takes the same lock in the same order, so the two serialize.
- **The fingerprint is what makes resume safe.** `sha256(document_digest |
  provider | model | sha256(effective prompt) | chunker_version)`; a mismatch
  deletes the whole set and restarts at 0 (`#871 chunk resume invalidated:
  <components>`), because a preview must never mix two chunkings, two models or
  two prompts. The components are stored next to the hash so the log can *name*
  what changed. Bump `core::ai::preview::CHUNKER_VERSION` whenever
  `extract_scenes` changes what a chunk is.
- **Progress and ETA measure from the resume point.** `progress.resumed_from`
  carries "n chunks already stored"; `progress.chunk` keeps its documented
  meaning (1-based index of the last completed chunk **of this attempt**). A
  client derives the rate from `chunk - resumed_from` and the remaining count
  from `chunks_total - chunk` — using the absolute counter would read "25 chunks
  in one second" and then declare a healthy successor chunk stalled.
- **Cost: every paid call is counted once.** The chunk row carries its usage, and
  `ON CONFLICT … DO UPDATE` *replaces* a re-run chunk's usage instead of adding
  it, so the completion snapshot sums all chunks regardless of which attempt paid
  for them. **One case is deliberately uncounted:** a call whose response arrived
  but whose row never persisted (a kill between response and insert). Its spend is
  bounded by one chunk per crash, it appears in no other surface, and it is not
  guessed at.
- **Cleanup.** Terminal transitions (`mark_succeeded`, `mark_payload_unavailable`,
  the dead-letter branch of `mark_failed`) delete the job's chunk rows in the same
  statement; a job that merely backs off keeps them — that is the resume. The
  payload-GC sweep deletes them with the blobs (skipped in dry-run), and
  `dev_reset` registers the table before the job delete.
- A schedule import is ONE extraction unit, so it has no chunk resume; the port is
  only consulted by the script worker.

#### Retry precedence (issue #871, workstream C)

Two nested layers, and **which one wins is a rule, not an accident**:

| Situation | What happens | Why |
|---|---|---|
| A retryable provider failure, breaker still **closed** | `retry_bounded` retries in-attempt, `AI_IMPORT_MAX_ATTEMPT_RETRIES` times (default 2) | a blip is cheap to absorb; the permit stays held (releasing and re-acquiring per retry would let another job interleave between two calls of the same chunk) |
| The breaker **opens** (threshold consecutive failures for the pair) | every held/runnable job of that pair takes the **hold** path; `next_attempt_at` = the breaker's `retry_at` | the whole fleet re-probes at ONE instant instead of a per-job stagger, which is what makes the single CAS prober cheap and recovery fast |
| A **non-provider** retryable failure (mapping DB, payload storage, pricing read model) | the ordinary per-job curve `1 min · 2^retries`, capped at 6 h | that curve was designed for exactly these, and the breaker must not swallow them — they say nothing about the endpoint |
| The **hold expires** (`AI_IMPORT_MAX_PROVIDER_HOLD_SECS`) | `dead_letter` with the provider narrative, `retries` **unchanged**, exactly one attempt row | the document did not fail, the provider did; the operator's "documents that failed" count must not be inflated by infrastructure |

**The permit is held across in-attempt retries and released with the attempt.** A
hold *ends* the attempt, so a waiting job occupies no capacity. The window one
attempt can occupy a permit is therefore a computed number, not a guess:

```
(1 + AI_IMPORT_MAX_ATTEMPT_RETRIES) × (1 + inner_retries) × AI_IMPORT_REQUEST_TIMEOUT_SECS
  + AI_IMPORT_MAX_ATTEMPT_RETRIES × max(30 s, MAX_IN_ATTEMPT_HINT_SECS)
```

with `inner_retries = 2` for hosted providers (`HOSTED_INNER_RETRIES`) and `3` for
Ollama (`OLLAMA_INNER_RETRIES`) — the clients re-request a truncated/malformed
answer *inside* one attempt, so the two layers **multiply**. The backoff term is a
**ceiling over both** the computed cap (`MAX_ATTEMPT_BACKOFF_SECS`, 30 s) and the
server-hint clamp (`MAX_IN_ATTEMPT_HINT_SECS`, 120 s) introduced by issue #926,
because `retry_bounded` sleeps `max(computed, hint)`. With the defaults:
**22 min** hosted, **28 min** Ollama (pre-#926 these were 19/25 min, and a
`const` assertion in `bounds.rs` keeps the ceiling ≥ both clamps).
`AiImportBounds::attempt_worst_case_secs`
is the authoritative rendering and is asserted in `bounds_tests.rs`; the inner
counts are declared in `core` and read by the clients, so the arithmetic cannot
drift from the code it describes.

> **Intentional cost change (D-C1).** The in-attempt retry count dropped from
> **5 to 2** in issue #871. Before the split, one knob governed both layers, so a
> single chunk could cost `5 × 5 = 25` paid calls before anything surfaced, each
> holding a permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`. Three attempts per
> chunk is enough to tell a blip from an outage, and the breaker — not a long
> retry ladder — is what handles the outage. This is a deliberate behaviour and
> cost change, not a regression: an operator who wants the old ladder can set
> `AI_IMPORT_MAX_ATTEMPT_RETRIES`, and `AI_IMPORT_MAX_RETRIES` keeps its job-level
> meaning untouched.

#### Provider retry hints (issue #926)

Every hosted provider we integrate signals a rate limit with `429` plus
`Retry-After` / `X-RateLimit-*`. Since issue #926 that header is **acted on**:
the transport parses it into a `RetryHint`, the classification attaches `wait` to
the failing `DomainError::ServiceUnavailable` as `retry_after`, and the four
schedulers that already exist use it as a **minimum** delay.

**The one rule that must not be broken:** the hint is never slept through inside
the provider call. That call holds an `ai_import.concurrency_permit`, so an
in-request sleep would hold capacity for the hint's whole duration — the
nested-hold anti-pattern #871 removed (25 paid calls / 19–25 min permit-hold per
chunk). The hint propagates **up** as data instead.

| Scheduler | How the hint is used | Clamp |
|---|---|---|
| `workers::retry_bounded` (in-attempt chunk retry) | the wait becomes `max(computed backoff, hint)`; jitter stays on the computed backoff | `MAX_IN_ATTEMPT_HINT_SECS` = **120 s**, because the pause holds a permit |
| `queue::mark_failed` (job-level retry) | `next_attempt_at = now + max(1 min·2^retries, hint)` | **6 h**, the ladder's own literal cap; a larger hint is clamped and logged at `warn` |
| `core::ai::provider_health` (breaker probe schedule) | `retry_at = now + max(open window, hint)` — the probe selector already reads `retry_at <= now()`, so a hint-unexpired pair is not probed | `MAX_PROBE_DEFER_SECS` = `MAX_OPEN_SECS` (30 min): a probe is never deferred beyond the breaker's own maximum window |
| `ProviderHold.until` (hold series) | inherits `retry_at`, so a held job's `next_attempt_at` honours the hint too | bounded by `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` for the whole series |

Notes that keep this honest:

- **No new environment knob.** Both clamps are constants named above; only a
  future *policy* change (not a deployment tweak) would justify a knob, and it
  would need bounds plus startup logging like the existing ones.
- **A hint never changes the classification.** It does not touch the variant,
  the registered code (`ai-import.llm-provider-unavailable`), the HTTP status or
  `is_retryable()`. The *body*, not the header, is what separates an exhausted
  quota from a burst — see "Quota exhaustion vs rate limit (issue #927)".
- **The narrative names the rate limit.** The attempt row's `error_summary`
  says "… asked to wait Ns", and both the text and the typed field come from the
  one `retry_after` input at the classification boundary — `core` builds no
  presentation string (ADR-031).
- **A bad hint is never an error.** An absent, unparsable or absurd header
  degrades to "no hint" (or the one-day `MAX_SERVER_HINT` cap in the parser), and
  the request keeps its ordinary outcome.
- **A hint-less failure never shortens a deferral an earlier hint earned.** The
  `retry_at` write is unconditional, so the deadline is data on the row and
  `BreakerCounters` carries it into the state machine: while it is unexpired the
  probe keeps the later of it and the newly computed time. Without that, the
  60 s open window of the next ordinary `503` would pull a 10-minute rate-limit
  deferral forward and the probe would fire into a provider that is still
  rate-limiting us. An **expired** stored deadline is discarded — nothing is left
  to protect.
- **Not honoured, deliberately:** the decision-scoring pass
  (`decision_scoring::decide_with_quick_retry`) and the pricing-catalog ticker.
  The first carries the hint into the job-level retry but keeps its own single
  fixed pause (its policy is a bounded two-call pass, not a scheduling loop); the
  second has no retry loop at all.

#### Quota exhaustion vs rate limit (issue #927)

A provider `429` is **two conditions**, and only the response body tells them
apart. A rate limit (RPM/TPM) is fixed by waiting; a quota exhaustion is not —
retrying burns paid calls that are answered `429` again, each holding a
concurrency permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`, and then spends
the whole job retry budget to learn what the first response already said.

`client::classify_provider_body(provider, body) -> RateLimitVerdict` decides on
**evidence from the provider's own error text** (the #521 rule: verify before
attributing), and `classify_http_status_rich(…, verdict)` maps the terminal
verdict to `DomainError::LlmProviderQuotaExhausted`. That variant keeps the
**existing** registered code (#822 D-X1: no new code for provider narratives) but
is non-retryable, so the job dead-letters on the first attempt with the provider
code in its narrative.

| Provider | Terminal markers | Everything else on `429` |
|---|---|---|
| `openai`, `neuralwatt`, `opencode`, `opencode-go` | `insufficient_quota`, `credit_balance_exhausted`, `billing_hard_limit_reached` | retryable |
| `gemini` | `perdayperproject`, `per_day_per_project` (the RPD quota id in `error.details[].metadata.quota_limit`) | retryable |
| `openrouter` | `free-models-per-day`, `free_models_per_day` | retryable |
| `eurouter` | *(none — budget caps are `402`, its `429` is plan RPM)* | retryable |
| `ollama` | *(none — self-hosted)* | retryable |

Rules that must not drift:

- **The table is curated `const` data in the transport layer**, next to
  `CuratedProviderUrls`, and is **not** user-configurable — the same trust rule
  as the curated URLs. A new provider ships retryable until its evidence has been
  verified against a live response.
- **The conservative default is retryable.** An empty body, an unparsable one (an
  HTML gateway page), a read that failed, or an unknown code stays
  `RateLimited` + `debug`. A wrong "non-retryable" verdict dead-letters a job a
  retry would have saved; a wrong "retryable" one costs one attempt.
- **The verdict only narrows a `429`.** A `5xx` carrying a quota-looking body is a
  gateway fault and must never dead-letter a job. `402`/`403` keep their existing
  non-retryable rejection (EURouter budget caps, opencode entitlement).
- **`X-RateLimit-Remaining: 0` is not evidence**: an RPM window reaches zero the
  same way. Header-only turnstiles stay retryable; the #926 hint still schedules
  the retry.
- **The body read is bounded in bytes AND in time**
  (`client::MAX_ERROR_BODY_BYTES` = 1 KiB, and a deadline of
  `client::error_body_budget(request_timeout)` = `min(ERROR_BODY_DEADLINE = 5 s,
  AI_IMPORT_REQUEST_TIMEOUT_SECS)` — the knob is configurable down to 1 s, so the
  read can never outlive the request it belongs to; streamed chunk by chunk,
  never `text()`/`bytes()`): a chatty or hostile error page must not stream while
  a permit is held, and a marker behind the bound is deliberately not seen
  (conservative default). Say it as **limiting** the permit hold, not as always
  ending it before the timeout — at the knob's 1–5 s floor the budget equals the
  timeout, so the read may last as long as the request itself.
- **An incomplete read is not evidence.** The reader returns
  `ErrorBody { text, complete }`; an IO error or the deadline leaves
  `complete = false`, which keeps the `429` retryable even when the bytes that
  arrived look like a quota code (a proxy-cut stream may have lost the part that
  changes the meaning). A stream that ends on its own end — or on the deliberate
  byte bound — classifies normally.
- **The narrative names the matched code.** The verdict carries the curated
  marker that fired (`QuotaExhausted { marker }`), so the attempt row says
  `… no quota left (insufficient_quota)` even when a long `error.message` pushes
  the raw code past the 400-character detail truncation.
- **A terminal verdict never moves the breaker counter.**
  `retry_bounded` records a provider failure only for a *retryable* one; counting
  a quota exhaustion would let three of them open the breaker, and the hold that
  follows would park a job that has nothing left to wait for.

#### Durable apply run (issue #899)

The **apply** used to be request-scoped: `apply_ai_import` awaited
`ApplyWorker::apply_script` in the handler future, so a client that vanished
(Android Doze, Wi-Fi→cellular handover, a closed socket) dropped the future and
the run stopped mid-row. It is now a work item on the job row, exactly like the
preview job.

| Transition | Port method | Writes |
|---|---|---|
| dispatch | `request_apply_run(id, run_id, &ApplyRunRequest)` | `apply_state = requested`, `apply_request` (JSONB), `apply_result = NULL`, the claim (`apply_run_id`, `apply_claim_at`, `apply_run_seq + 1`) |
| worker claim | `begin_apply_run(id, takeover_run_id)` | `requested` → `running` **adopting** the dispatching run id, or a stale `running` → `running` under `takeover_run_id` (the dead owner's writes then fail the fence) |
| success / failure | `complete_apply_run(id, run_id, &summary)` / `fail_apply_run(id, run_id, code)` | `done`/`failed` + `apply_result` (`ApplyRunOutcome`), `apply_progress = NULL`, `apply_run_id = NULL` — owner-fenced, `Conflict` for a displaced run |
| poll | `requested_apply_runs(limit)` | the rows a worker may claim: `requested`, or `running` silent for `ApplyProgress::STALE_AFTER` (the same window the single-flight steal uses) |

Rules that must not drift:

- **The handler never executes a run.** `POST /apply` validates, persists and
  answers `202 ApplyRunAccepted`. Row work happens in
  `api::apply_runner::spawn_apply_run_worker` → `ApplyRunner::run_claimed`.
- **`apply_request` is the reviewer's decision set**, resolved at the API edge
  (target episode/season/block, mapping decisions, group targets, day decisions,
  acknowledgements, continuity selections, the season's category vocabulary, the
  episode labels). The worker must never re-derive it from a projection (CQRS
  boundary) and never read it back out to a client — it is not in the job DTO.
- **The outcome is persisted, not returned.** The terminal frame of
  `GET /jobs/{id}/apply-events` and `GET /jobs/{id}` serve it (`apply_state` +
  `apply_result`); a failed run carries the registered problem **code**.
- **`ApplyProgress` is cleared only by the terminal transitions.** A run killed
  mid-flight leaves `running` + a stale stamp, which the takeover path reclaims —
  do not re-introduce a drop guard on the dispatched path.
- **A live run renews its own claim** (`renew_apply_run`, issue #911). Every
  single-flight predicate above is silence-based, which a *script* apply satisfies
  with its progress frames and a *schedule* apply cannot: it is one merge loop
  over the project's existing scenes and days and publishes nothing, so before
  #911 a schedule run that outlived `ApplyProgress::STALE_AFTER` was taken over
  **while it was still executing**. `ApplyRunner::run_claimed` therefore runs the
  execute future under `infra::ai::with_apply_run_lease` (interval = a third of
  that window). The renewal rides the run's own future instead of a spawned task,
  so it dies with the task and a crashed replica still becomes stealable after one
  window. It writes `apply_claim_at` **only** — never the payload (that would
  invent progress), never `apply_run_seq`, never a `pg_notify` — and `false`
  (displaced, or the run already finished and freed the slot) stops the loop.
  All four silence predicates (both steals, the takeover and the poll) compare the
  **newer** of the payload's `updated_at` and that lease stamp
  (`COALESCE(GREATEST(…, apply_claim_at), updated_at)`), so the renewal also covers
  a script run that is between frames — a schedule run has none at all.
  `ApplyRunState::owner_silence_at` mirrors that `GREATEST`, because the age a
  client reads in the `409` must describe the same decision the server makes.
- **Shutdown joins**: the loop aborts-and-joins its in-flight runs before the
  pool teardown; an interrupted run is recovered by the staleness window, never
  rolled back (the protocol stays idempotent-and-converging).
