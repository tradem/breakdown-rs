// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Shoot Day (Actual / Ist) Report Template
// Reads data from report.json via the restricted virtual filesystem.

#set page(paper: "a4", margin: 2cm)
#set text(font: "Noto Sans", size: 10pt, lang: "de")

#let data = json("report.json")

#align(center)[
  #text(size: 16pt, weight: "bold")[Drehtag-Bericht]
  #v(0.5cm)
]

#let rows = data.rows

#if rows.len() == 0 [
  #align(center)[
    #text(style: "italic")[Keine Daten vorhanden]
  ]
] else [
  #table(
    columns: (auto, auto, auto, auto, auto, auto, auto, auto),
    align: (center, center, left, left, left, left, left, left),
    [*Ist-Reihenfolge*], [*Szenen-Nr*], [*Script-Tag*], [*Ort*], [*Status*], [*Start*], [*Ende*], [*Notizen*],
    // `cell(...)` (see `_helpers.typ`) is mandatory for every table cell:
    // `row.scene_number` / `row.notes.len()` are raw integers and abort
    // compilation with `expected content, found integer` (issue #764).
    ..rows.map(row => (
      cell(row.actual_order),
      cell(row.scene_number),
      cell(row.script_day),
      cell(row.location),
      cell(row.status),
      cell(row.start_dt),
      cell(row.end_dt),
      cell(row.notes.len()),
    )).flatten()
  )
]
