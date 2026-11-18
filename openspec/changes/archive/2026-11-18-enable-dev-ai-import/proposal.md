<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# enable-dev-ai-import (issue #428)

> One-liner to enable AI import for the host-run dev API: Garage port
> override + payload env. Implemented directly (dev-infra change; no wire
> contract or spec deltas).

## Why

Enabling `AI_IMPORT_ENABLED=1` for a host-run `cargo run -p api` currently
fails closed (per #181 — no silent in-memory payload fallback) unless durable
payload storage is configured. The dev compose's Garage service is
deliberately internal-only (no host port mapping), so the host-run API cannot
reach it, and manual multi-step configuration (port mapping + provisioning +
env) blocked device-testing sessions (#422 context).

## What Changes

- **Compose:** the base dev compose (`docker-compose.dev.yml`) renders the
  Garage TOML via the prod `garage-config` one-shot pattern (before this the
  dev Garage crash-looped — invalid RPC secret default + missing config; its
  CMD-SHELL healthcheck could never spawn in a shell-less image). New
  `docker-compose.dev.ai.yml` overlay publishes Garage's S3 (:3900) and admin
  (:3902) ports to the host — dev-only plaintext, fail-closed startup gate
  (#181) untouched.
- **Script:** `scripts/enable-dev-ai-import.sh` — idempotent one command:
  boots dev + AI overlay, provisions layout/buckets/dev-only S3 key via
  `docker compose exec` (the garage image is a bare binary without a shell),
  verifies host reachability, and writes `.env.dev-ai.local` (git-ignored,
  chmod 600) with the full host-run env. `--run` additionally starts the API.
- **Bugfix found on the way:** `shutdown_ai_import` re-awaited worker
  `JoinHandle`s already consumed by the bounded join poll — every graceful
  shutdown with AI import enabled panicked ("JoinHandle polled after
  completion"). Fixed in `crates/api/src/main.rs` (`join_worker_with_budget`)
  with three regression tests; rides with the open 0.10.0 MINOR.
- **Docs:** local-dev-runtime + ai-import instruction files updated.

## Impact

- No env var *semantics* change; no OpenAPI drift; no crate version bumps
  (behavior bugfix rides with the open unreleased 0.10.0).
- Security posture unchanged: dev-only plaintext Garage ports are an explicit
  overlay opt-in and bound to `127.0.0.1` only (never LAN-reachable); ADR-024
  `REQUIRE_IN_TRANSIT_TLS` gate untouched; derived dev-only credentials carry
  a never-reuse-outside-dev note.
