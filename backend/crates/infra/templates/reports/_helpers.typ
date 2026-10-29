// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Shared report-template helpers (issue #764).
//
// This file is *not* a report template: `embedded_templates()` prepends its
// source to every `*.typ` template of this directory, so the definitions below
// are available to all report kinds without a Typst `#import` (the restricted
// virtual filesystem of the renderer only serves `main.typ` + `report.json`).
//
// --- Table cells -----------------------------------------------------------------
//
// A Typst table cell must be `content`: passing a raw JSON number or boolean
// aborts compilation with `expected content, found integer`. That shipped and
// turned every non-empty report into an opaque HTTP 500 (issue #764), because
// no test rendered a template with row data.
//
// `cell` normalises *any* JSON scalar so a new numeric/boolean column cannot
// reintroduce the failure:
//   none          -> ""            (empty cell, no "none" text)
//   str, content  -> unchanged
//   everything    -> repr(v)       (integer/float as digits, boolean as
//                                   `true`/`false`, arrays/dicts as Typst repr)
//
// Convention: wrap **every** table cell in `cell(...)`. Where the semantics are
// known (e.g. Soll-Ist flags), map them to German labels at the call site
// (`if row.moved { "Ja" } else { "–" }`) — `cell` is the safety net, not the
// formatting policy.
#let cell(v) = if v == none {
  ""
} else if type(v) in (str, content) {
  v
} else {
  repr(v)
}
