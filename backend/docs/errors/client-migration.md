<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# Client Migration: `message` → `code`

This page describes the breaking change from the legacy ad-hoc error bodies to
the RFC 9457 problem-detail surface (ADR-031). All three first-party clients
(Svelte web, Flutter, Slint) must switch their error handling to branch on
`code` — the `detail` text is localized and must never be parsed.

## What changed

| | Legacy | Now |
|---|---|---|
| Body shape | `{ "message": "…" }` | RFC 9457 problem+json (see [README.md](README.md)) |
| Machine identity | none (status + prose only) | `code` (`{context}.{reason}`, stable) |
| Localization | English-only, embedded at error construction | server-side `detail` via `Accept-Language` |
| Domain validation status | 400 | **422** |
| Params | none | typed `extensions` per code (whitelisted) |
| Correlation | none | `trace_id` |

The body-shape and 400→422 changes are done together so clients migrate once.

## Migration steps

1. **Treat every HTTP error response (`status >= 400`) as a problem document.** Parse
   `application/problem+json` (Axios `response.data`, `http`/`dio` body,
   Slint `HttpResponse.body`); extract `code`, `status`, `detail`,
   `trace_id`, `extensions`. 3xx redirects are not problem documents.

2. **Branch on `code`, never on `detail`.** Replace every
   `message.includes("not found")`-style check with the corresponding code.
   The full catalogue is [error-codes.md](error-codes.md); the OpenAPI
   `x-code-registry` extension carries the same data machine-readably.

3. **Handle the status split.** Domain validation failures now arrive as
   422, not 400. Keep 400 handling for genuinely malformed requests
   (`http.bad-*` codes); route `{agg}.validation` / `domain.validation` to
   your form/validation UI.

4. **Use `extensions` for context, not prose.** Example: a version conflict
   arrives as `concurrency.version-mismatch` with
   `extensions.expected_version` / `extensions.current_version` — show a
   "reload" action instead of echoing the German `detail`.

5. **Expose `trace_id` on support surfaces.** A screenshot with
   `code` + `trace_id` maps 1:1 to server telemetry (otel).

6. **Never localize client-side from `detail`.** If your client needs other
   locales, branch on `code` + `extensions` and translate client-side — the
   server sends `de` (default) or `en` per `Accept-Language`.

## Client-specific notes

- **Svelte (web):** centralize in one fetch/axios interceptor; keep a
  `code → message` map for UX strings; surface `trace_id` in the support
  dialog.
- **Flutter (dio):** a `ProblemDetails` model class with `fromJson`; use
  `DioException.response?.data`; map codes to `Failure` objects in the
  repository layer so widgets stay code-agnostic.
- **Slint:** parse the JSON body (e.g. via a small Rust helper on the
  business-logic side) and hand the UI a `code` enum; Slint views never
  parse raw error text.

## Fallback

If a response is unparseable or the `code` is unknown, degrade to
`http.internal-error`-style handling:

- **Never log the raw response body** — it can carry PII, credentials, or
  upstream diagnostics. Log the status and `trace_id`, plus at most a
  bounded, redacted excerpt when diagnostics require it.
- Show a generic "something went wrong" message to the user.
- **Retry only documented transient codes** (e.g. `domain.service-unavailable`
  / 503), never every 5xx, and only for idempotent requests or requests
  carrying an idempotency key. `http.internal-error` is opaque by design and
  must not be retried.
