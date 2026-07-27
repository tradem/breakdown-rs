// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

// Planned vs Actual (Soll-Ist-Vergleich) Report Template
// Reads data from report.json via the restricted virtual filesystem.

#set page(paper: "a4", margin: 2cm)
#set text(font: "Noto Sans", size: 10pt, lang: "de")

#let data = json("report.json")

#align(center)[
  #text(size: 16pt, weight: "bold")[Soll-Ist-Vergleich]
  #v(0.3cm)
  #if data.is_final [
    #text(size: 10pt, weight: "bold", fill: green.darken(20%))[Finale Version]
  ] else [
    #text(size: 10pt, fill: gray)[Vorläufig]
  ]
  #v(0.5cm)
]

#let rows = data.rows

#if rows.len() == 0 [
  #align(center)[
    #text(style: "italic")[Keine Daten vorhanden]
  ]
] else [
  #table(
    columns: (auto, auto, auto, auto, auto, auto, auto, auto, auto),
    align: (center, center, left, left, left, left, center, center, center),
    [*Szenen-Nr*], [*Script-Tag*], [*Ort*], [*Soll*], [*Ist*], [*Verschoben*], [*Fehlend*], [*Übersprungen*], [*Nachgedreht*],
    ..rows.map(row => (
      row.scene_number,
      row.script_day,
      row.location,
      row.planned_order,
      row.actual_order,
      if row.moved { "Ja" } else { "–" },
      if row.missing { "Ja" } else { "–" },
      if row.skipped { "Ja" } else { "–" },
      if row.reshot_candidate { "Ja" } else { "–" },
    )).flatten()
  )
]
