// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

// Dispo (Planned / Soll) Report Template
// Reads data from report.json via the restricted virtual filesystem.

#set page(paper: "a4", margin: 2cm)
#set text(font: "Noto Sans", size: 10pt, lang: "de")

#let data = json("report.json")

#align(center)[
  #text(size: 16pt, weight: "bold")[Dispo-Bericht]
  #v(0.5cm)
]

#let rows = data.rows

#if rows.len() == 0 [
  #align(center)[
    #text(style: "italic")[Keine Daten vorhanden]
  ]
] else [
  #table(
    columns: (auto, auto, auto, auto, auto, auto),
    align: (center, center, left, left, left, left),
    [*Reihenfolge*], [*Szenen-Nr*], [*Script-Tag*], [*Ort*], [*Stimmung*], [*Zusammenfassung*],
    ..rows.map(row => (
      row.planned_order,
      row.scene_number,
      row.script_day,
      row.location,
      row.mood,
      row.summary,
    )).flatten()
  )
]
