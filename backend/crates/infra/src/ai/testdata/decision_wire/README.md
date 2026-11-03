<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# System One wire fixtures (issue #808)

These files speak the **provider's** contract, not ours. That is the whole
point: the unit tests this directory feeds mocked the provider with our own
assumption (`score` as a distribution, no request-shape check at all), so the
suite stayed green while every live scoring call answered
`400 Invalid request` (issue #808).

| File | Kind | Provenance |
|---|---|---|
| `error_400_invalid_request.json` | provider 400 | verbatim from the live probe (2026-11-03) of `POST https://api.eurouter.ai/api/v1/systemone` |
| `answer_noul_200.json` | 200 envelope | live probe answer `{"type":"noul","noul":0.461}` wrapped in the envelope; `usage` verbatim (`cost` elided in the issue, filled with a representative value — the adapter ignores it) |
| `answer_score_200.json` | 200 envelope | live probe answer; `0.0149`/`0.5432`/`score: 3.2361` verbatim, the three middle probabilities reconstructed so the map sums to 1.0 and averages exactly `3.2361` |
| `answer_choice_200.json` | 200 envelope | live probe answer, verbatim (`costume`/`props` were the probed option names) |
| `answer_score_legend_mismatch_200.json` | 200 envelope | synthetic: the live `score` answer with a `legend` that is **not** the ladder we sent |
| `answer_score_empty_probabilities_200.json` | 200 envelope | synthetic: the live `score` answer with an empty mass map |
| `question_noul.json` / `question_score.json` / `question_choice.json` | request goldens | the **production** rubric questions (`script_chunk_questions()` / `continuity_questions()`) rendered by `decision_client::question_payload` |

`question_*.json` are goldens: a change to the request shape (or to a rubric
label/option) must update them deliberately. They pin the exact key sets —
`instructions` present, `criteria` present for `score`/`choice`, and the
pre-#808 names `description` / `options` / `levels` absent — because a single
wrong field rejects the whole body, not just that question.

Fixtures are never refreshed automatically. A provider-side schema change is
detected by the opt-in live smoke test
(`decision_client_tests::live_systemone_answers_every_question_kind`, see
`docs/operations/runbooks.md`), not by these files.
