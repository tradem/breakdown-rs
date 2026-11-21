<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## Backend API image release `api-v0.71.0`

This is the Docker image release of the Breakdown backend API (ADR-020 D6).
It covers everything accumulated since `api-v0.14.0` (2026-10-04) — 221
commits (108 of them backend), condensed into the `api-v0.71.0` section of
[`backend/CHANGELOG.md`](https://github.com/tradem/breakdown-rs/blob/main/backend/CHANGELOG.md).

### Deploying

Pull the **immutable** version tag (SHA-pinned digest):

```
ghcr.io/tradem/breakdown-rs:api-v0.71.0
```

Moving tags `api-v0.71` (latest patch) and `api-v0` (latest minor) are also
published. The rolling `:latest` tag is deliberately **not** published — pin
by `api-vX.Y.Z` for reproducible rollbacks.

The image brings **28 additive Postgres migrations**; they run through the
usual migrator path (`MIGRATOR_DATABASE_URL`) at startup. No event-store
migration and no projection backfill is required.

### Upgrading from `api-v0.14.0` — read this first

- **Wire (breaking): `series_id` → `project_id`.** The 29 OpenAPI
  `series_id` properties and the `?series_id=` query parameters are now
  `project_id` (ADR-035 layers 1–3, issues #591/#599). Persisted event
  payloads keep `series_id`, deliberately and permanently; only the read
  model and the wire moved. No `/v2` path version was cut — a recorded
  deviation from the issue's acceptance criteria.
- **Domain (breaking): the wardrobe is `Piece` + `Outfit`.** A fundus
  garment with one optional category, and a character's composed, layered
  look with `variant_of` forks. Scenes cast outfits, never bare pieces
  (OpenSpec change `separate-piece-and-outfit-domain`).
- **Behaviour: an AI-import apply is asynchronous.** `POST
  /v1/ai-import/jobs/{id}/apply` answers `202` and a run owns the row loop;
  progress is read from the apply stream, not from the request.
- **Internal Rust API (breaking for a workspace consumer, not for clients):
  `jiff` replaces `chrono`** (`RUSTSEC-2026-0543`, ADR-040). No wire or
  persisted-payload change — the byte-identity claim is a test
  (`pre_migration_timestamps_round_trip_byte_identically`).

### Highlights

**AI import became an operation you can trust**

- A durable, resumable apply run: dispatch `202`, run identity, liveness
  signal, single-flight gate, lease renewal, per-run append/`WRONGVER` and
  Postgres-time attribution (issues #800, #805, #863, #864, #899, #900,
  #911).
- A deployment-wide `(provider, model)` circuit breaker, held jobs that
  persist the failure that parked them, chunk-level resume with a derived
  cursor and a measured ETA (issues #822, #871, #942).
- Honest retry policy: a provider's `Retry-After` / `X-RateLimit-*` is a
  **minimum** delay, never a sleep that holds a concurrency permit; a
  quota-exhausted `402`/`429` is terminal with its own
  `ai-import.provider-quota-exhausted` code; an empty completion is a
  provider failure (issues #925, #926, #927, #945).
- Targets: upload to a season, attach the block later, freeze the target at
  review, refuse contradictions, and honour the script's own block (issues
  #763, #771, #827, #829).
- Extraction: episodes, shooting days, character categories, `DraftOutfit`s
  with derived `DraftPiece`s, and cross-scene outfit continuity in a second
  pass (issues #581, #677, #695, #706).
- Cost transparency: per-import cost, Decision-Model token/energy pricing on
  its own rate card, persisted Decision-Model scene scores, an optional
  `reasoning_effort` per AI config, and a dedicated read-model pool so an
  apply no longer queues behind its own projection backlog (issues #675,
  #767, #834, #900, #923, #946, #948, #949).

**Domain and reports**

- ES-native reservation streams make cross-aggregate uniqueness atomic at the
  write boundary: a racing numbering or `scene_shoot` command answers `409`
  with no losing aggregate event (issue #586, ADR-036).
- Project-scoped costume roles: a department role is block-scoped or
  project-scoped, resolved fail-closed through one port method
  (OpenSpec change `project-scoped-membership`).
- Season lifecycle (`ArchiveSeason` / `SeasonArchived`) and season repertoire
  as real aggregate state (issues #533, #534).
- Season-/episode-scoped aggregated Soll-Ist reports (issue #571); PDF report
  downloads fixed — real font discovery, no silent empty renderer (issues
  #642, #764, #766).

**Security and hygiene**

- `rustls 0.23.46` and `hickory-proto 0.26.3` close the advisories published
  since the last cut; `cargo deny check advisories` is green without a
  workspace ignore.
- `AUTHZ-GATE` predicate errors surface as `500` instead of a swallowed
  `403` (issue #537); a leftover `DEV_AUTH_SUB` no longer defuses
  `AUTHZ_ENFORCE` (issue #935).

### Assets in this release

| Asset | Content |
|---|---|
| `architecture-v0.71.0.pdf` | arc42 architecture documentation (PDF) |
| `architecture-v0.71.0.html` | the same documentation as a single-page HTML |

Both are built by the `Docs Build & Publish` workflow from
`backend/docs/architecture/arc42-typst/` — the same sources that publish the
latest HTML to GitHub Pages.

Companion crate versions at this release: `core 0.75.0`, `infra 0.86.0`,
`api 0.71.0`.
