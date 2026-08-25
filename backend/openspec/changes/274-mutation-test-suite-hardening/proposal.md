<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Proposal: Mutation-Test-Hardening (Issue #274)

## Warum

Der Weekly-`cargo mutants`-Run 32800458579 lieferte **516 überlebende (missed) Mutanten**
(Verteilung: `infra` 360 · `api` 81 · `core` 75) plus 6 hängende Mutanten (Timeouts).
Das Issue #274 fordert, die Testlücken systematisch zu schließen — bevorzugt durch
killende Tests, `exclude_re` nur mit Einzelfall-Begründung.

## Ansatz

Statt eines Monolith-PRs wird die Arbeit in **6 Batches** (ein PR je Batch) und
**45 Patches** (je ein Datei-/Cluster-Fix ≙ ein Commit) zerlegt. Die vollständige
Task-Liste mit allen 516 Mutanten, Kill-Strategien und Verify-Kommandos liegt in
**[tasks.md](./tasks.md)** — jeder Patch ist ein eigenständiger Abschnitt mit
Statuszeile, sodass einzelne Patches session-übergreifend bearbeitet werden können.

| Batch | Fokus | Priorität | Patches | Survivor |
|---|---|---|---|---|
| 1 | Security & Crypto (`auth/authorization`, `tls`, `vault`, `settings/ports`, `tls_config`) | P0 | 5 | 35 |
| 2 | Authz-Handler 403-Tests (`api/handlers/mod.rs`) | P0 | 5 | 54 |
| 3 | AI-Import (`infra/ai/**`, `core/ai/**`) | P1 | 17 | 187 |
| 4 | Audit & Reporting (`projectors/*`, `reporting/*`) | P1 | 5 | 102 |
| 5 | Photo-Sagas & GC | P1 | 5 | 63 |
| 6 | Queries & Diverses (Queries, Shutdown, CLI-Bin, Problem-Surface) | P2 | 8 | 75 |

Enthalten sind zusätzlich die **Timeout-Härtungen** aus dem Issue (bounded retry loops
in `vault::ensure_key` / `photo_sse_c_wrapped_key` sowie clamp für
`permit_renewal_interval`), damit die 6 hängenden Mutanten code-seitig verschwinden.

## Risiken / Out of Scope

- Das companion-Infra-Issue #273 (Pipeline-Baseline-Failures, Shard-Timeouts) ist
  bewusst **nicht** Teil dieser Änderung.
- P0-Patches müssen ohne Docker lauffähige Tests liefern (Acceptance Criteria).
