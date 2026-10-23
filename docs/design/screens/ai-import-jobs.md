<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# AI-Import-Aufträge (ai-import-jobs) — Screen Spec

## Purpose & Context

The persistent "what did I import" surface (issue #547): every AI-import
job the user started stays reachable after leaving the job-status screen.
It closes the silent dead-letter hole — a job that ends in
`dead_letter` or `payload_unavailable` after the user navigated away was
previously unlearnable. The list renders the caller's jobs newest-first
from the cache-then-revalidate `aiImportJobsView` projection.

## Navigation

Reached from the main **Settings** screen's AI section — the
persistent "KI-Import-Aufträge" tile (issue #644): always reachable,
even when zero jobs need attention. Two further paths: the
production-overview **active-jobs summary row** (shown while any known
job needs attention) and, from the jobs screen's empty state, the CTA
into the import entry. Every push carries `RouteSettings(name:
'ai-import-jobs')`, so the apply outcome's "back to imports"
`popUntil` contract resolves from any entry. Row selection pushes the job
status screen (`AiJobStatusScreen`) — the screen that owns the single
foreground status watch; back returns to the caller. No route parameters.
AUTHZ-GATE: the jobs list route is ownership-scoped server-side; the
client resolves the authenticated session before the fetch (no session →
no request) and denials surface through code-keyed copy
(`jobWatchForbidden` / `aiJobsLoadError`), never backend `detail`. The
sibling production-overview import entry keeps its block-scope gate —
this screen does not weaken it (it dispatches no block-scoped write).

## Layout

```plantuml
@startsalt
{
  "KI-Import-Aufträge"
  ==
  "Verbindung gestört" — Banner, nur wenn stale
  --
  {^ "⏳" "Drehplan · 1. Jan. 2026"
     "Dein Dokument wird verarbeitet …"}
  {^ "⛔" "Drehplan · 1. Jan. 2026"
     "Die Verarbeitung hat nach wiederholten Fehlern aufgegeben." [!]}
  {^ "✔" "Skript · 2. Jan. 2026"
     "Import-Vorschau bereit."       [›]}
}
@endsalt
```

Expanded (window width class ≥ medium): the same single-column list
constrained to a content max-width with wider gutters — a jobs list never
splits into master/detail panes; the detail surface is the pushed status
screen, on every window size.

## Components & Semantics

| Element | M3 component | Semantics | Copy key |
|---|---|---|---|
| Screen title | Top app bar | Screen identity (plural) | `aiJobsTitle` |
| Job row | List item | Pushes the job status screen (the single-watch owner) | row key |
| Row title | Text | Document kind + created date, e.g. „Drehplan · 1. Jan. 2026" | `aiJobsRowSubtitle` |
| Row status | Text | One of the six honest status copies, always visible next to the icon | `aiImport.jobStatus` |
| Status icon | Icon | Per-status glyph (see glossary); error-colored for terminal failures — reinforcement only, never the sole carrier | status glyphs |
| Retry budget | Text | Retryable `failed` rows show `Versuch {retries} von {maxRetries}` | `aiJobRetryBudget` |
| Row stage | Text | Running rows with a published `progress` show the localized extraction stage (issue #664) | `aiJobStage*` |
| Row episodes label | Text | Running rows with discovered episodes show the `Gefundene Episoden:` summary line (issue #664) | `aiJobEpisodesSeenLabel` |
| Last-error indicator | Icon | Presence indicator on rows carrying a server error detail; the raw text renders only on the status screen, as secondary detail | status glyph |
| Stale banner | Banner | Failed refetch serving retained cached rows | `seasonsStaleBanner` |
| Error state | Card + button | Copy keyed on the problem `code`; retry re-runs the list route | `aiJobsLoadError` / `aiJobCheckAgain` |
| Empty state | Icon + text + button | Honest "no import yet" + CTA into the import entry | `aiJobsEmpty` / `aiJobsEmptyCta` |
| Settings AI-imports entry | List item (push, chevron) | Persistent entry from the Settings AI section (issue #644) | `settings.aiImports` + `settings.aiImportsSubtitle` |
| Production-overview summary row | List item | Visible while any known job needs attention (any non-`succeeded` status) | `planningActiveJobRow` / `aiJobsActiveBadge` |

## States

Loading: skeleton rows (visible only before the very first cache seed —
the cached-first paint makes cold starts render rows immediately). Data:
newest-first rows. Empty: honest "no import yet" with the import CTA.
Error: full error state when no rows are retained; a banner above the
retained rows otherwise — both keyed on the stable problem `code`, never
`detail`. Stale: the shared cache-staleness banner when a failed refetch
left only cached rows. There is NO optimistic layer: this boundary
dispatches no commands.

## Interactions

Row tap pushes the job status screen, which arms the single foreground
watch (D5) and owns the re-arm (`aiJobCheckAgain`) and preview
(`aiJobReviewPreview`) affordances; leaving it disposes the watch. The
list itself arms NO watch and dispatches nothing — pull-to-refresh
re-runs exactly the list route, which is the status authority for rows;
there is no per-row polling and no fabricated progress indicator (the
wire carries `retries`/`max_retries`, never a percentage; since issue
#664 a running row MAY carry a server-published `progress` stage/chunk
summary — rendered from the fetched row only, never from a client-side
stream or fabricated count). The production-overview summary row and the
Settings AI-imports entry push this screen and never arm a watch — the
SSE stream (`GET /v1/ai-import/jobs/{id}/events`, issue #664) is opened
exclusively by the job status screen while foregrounded.

## Input & Validation

N/A — read-only screen (no forms, no commands).

## Accessibility & i18n

Every row renders its meaning as visible text (kind, date, status, retry
budget, and for running rows the stage/episode summary); icons reinforce
only and terminal failures additionally use the error color, so color is
never the sole carrier either. All copy via the ARB catalogs (`aiJobs*`,
`jobStatus*`, `jobWatch*`, `aiJobRetryBudget`, `aiJobStage*`); 
backend `detail` text never renders on this screen. Row semantics announce
kind + date + status.

## Preview & Apply — Decision Model star ratings (issue #723)

When the configured Decision Model scored the extraction, the preview
and apply cards render calibrated scores as **1–5 star ratings** via the
shared `AiScoreStars` component (`lib/design/components/`):

| Element | M3 component | Semantics | Copy key |
|---|---|---|---|
| Scene / synopsis / shooting-day score | Icon row (`star` filled vs. `star_border` outline) + label | Machine-evaluated review aid — never a decision; renders NOTHING when the score is `null` (honest absence, no Decision Model / failed pass) | `aiPreviewSceneScore`, `aiPreviewSynopsisScore`, `aiPreviewShootingDayScore`, `aiScoreStarsLabel` |
| Day-group score (apply card) | Icon row on the decision row | Same mapping, aggregated per day group (`DraftShootingDay.score`) | `aiScoreStarsLabel` |
| Low-score filter | `FilterChip` pair above the rows | Narrows the VISIBLE rows to any score `<= 3★` (`< 0.70`); the apply payload keeps every row — filtering is view-only | `aiPreviewFilterAll`, `aiPreviewFilterLowScore` |
| Banner note (scored) | Tertiary banner text | Frames the stars as machine-evaluated under EU AI Act Art. 50; the unscored note (`aiPreviewAiNote`) stays when no score exists | `aiPreviewAiNoteScored` |

The Decision / Scoring Model itself is configured on the AI config screen
(provider + curated model picker, "Use same API key as extraction" toggle,
separate split-billing key field — keys `aiConfigDecision*`); see the
`flutter-ai-config` OpenSpec spec.

## Tests

Widget tests: rows render kind + date + status text + icon; tap pushes the
status screen (watch-call proof: zero before the tap); empty state + CTA;
error state per `code`; stale banner over retained rows; terminal-failure
distinctness; production-overview summary row visible/hidden matrix and
navigation; Settings AI-imports entry push + back-to-Settings contract
(issue #644).
Unit tests: cache-then-revalidate ordering, no-watch assertion (D5),
remembered-id fast-path seed ordering, `forgetJob` reconciliation, status
label matrix (all six), code-keyed error copy. Goldens:
`ai_jobs_light_android`, `ai_jobs_dark_android`, `ai_jobs_light_macos`,
`ai_jobs_dark_macos`. Tier-4 integration is deliberately not added (the
tier-2 tests cover the return path with a mocked API; recorded decision).
