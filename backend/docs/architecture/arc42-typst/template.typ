// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

// arc42 Typst template for Breakdown RS architecture documentation.
// Based on: https://arc42.org/template/

#let doc(
  title: str,
  subtitle: str,
  version: str,
  date: str,
  authors: array,
  co-authors: array,
  body,
) = {
  // Document metadata
  set document(
    title: title,
    author: (authors + co-authors).join(", "),
  )

  set page(
    paper: "a4",
    margin: (left: 2.5cm, right: 2.5cm, top: 3cm, bottom: 3cm),
    numbering: "1",
    header: context {
      if counter(page).get().first() > 1 [
        #set text(size: 9pt, fill: gray)
        #title #h(1fr) arc42 Architecture Documentation
        #line(length: 100%, stroke: 0.5pt + gray)
      ]
    },
    footer: context [
      #set text(size: 9pt, fill: gray)
      #counter(page).display("1") #h(1fr) Version #version #h(1fr) #date
    ],
  )

  set text(font: "Libertinus Serif", size: 11pt, lang: "en")
  set par(justify: true, leading: 0.65em)

  // Heading styles
  set heading(numbering: "1.1")
  show heading: it => {
    if it.level == 1 { pagebreak(weak: true) }
    if it.level == 1 {
      block(above: 2em, below: 1em)[
        #set text(size: 24pt, weight: "bold", fill: rgb(0, 51, 102))
        #it
        #line(length: 100%, stroke: 1pt + rgb(0, 51, 102))
      ]
    } else if it.level == 2 {
      block(above: 1.5em, below: 0.8em)[
        #set text(size: 18pt, weight: "bold", fill: rgb(0, 51, 102))
        #it
      ]
    } else if it.level == 3 {
      block(above: 1em, below: 0.5em)[
        #set text(size: 14pt, weight: "bold")
        #it
      ]
    } else {
      block(above: 0.8em, below: 0.4em)[
        #set text(size: 12pt, weight: "bold")
        #it
      ]
    }
  }

  show outline: it => {
    set heading(numbering: none)
    it
  }

  // Code block styling
  show raw: it => {
    if it.block {
      block(fill: rgb(245, 245, 245), inset: 10pt, radius: 4pt, width: 100%)[
        #set text(size: 9pt)
        #it
      ]
    } else {
      it
    }
  }

  show link: it => {
    set text(fill: rgb(0, 102, 204))
    it
  }

  set enum(indent: 1em)
  set list(indent: 1em)

  set table(
    stroke: (x, y) => (
      left: if x > 0 { 0.5pt + gray },
      top: if y > 0 { 0.5pt + gray },
    ),
  )
  show table.cell: it => {
    if it.y == 0 { strong(it) } else { it }
  }

  // Title page
  page(
    margin: (left: 2.5cm, right: 2.5cm, top: 5cm, bottom: 3cm),
    header: none,
    footer: none,
  )[
    #align(center)[
      #block(above: 3cm, below: 1cm)[
        #text(size: 32pt, weight: "bold", fill: rgb(0, 51, 102))[#title]
      ]

      #block(above: 1cm, below: 2cm)[
        #text(size: 18pt, style: "italic")[#subtitle]
      ]

      #block(above: 2cm, below: 1cm)[
        #text(size: 14pt)[Version #version]
        #linebreak()
        #text(size: 12pt)[#date]
      ]

      #block(above: 3cm)[
        #text(size: 14pt)[*Author:*]
        #linebreak()
        #text(size: 12pt)[#authors.join(", ")]
      ]

      #block(above: 1cm)[
        #text(size: 14pt)[*Co-authors:*]
        #for co in co-authors [
          #linebreak()
          #text(size: 12pt)[Co-authored-by: #co]
        ]
      ]

      #v(2cm)

      #text(size: 10pt, fill: gray)[
        Documentation generated with #link("https://typst.app/")[Typst] \
        Based on the #link("https://arc42.org/")[arc42] architecture documentation template
      ]
    ]
  ]

  pagebreak()
  outline(
    title: [Table of Contents],
    indent: auto,
  )

  body
}

// Admonition boxes
#let admonition(kind: "note", title: none, body) = {
  let styles = (
    note: (
      border: rgb(0, 102, 204),
      bg: rgb(230, 242, 255),
      icon: "ℹ",
      label: "Note",
    ),
    warning: (
      border: rgb(255, 153, 0),
      bg: rgb(255, 244, 230),
      icon: "⚠",
      label: "Warning",
    ),
    tip: (
      border: rgb(0, 153, 76),
      bg: rgb(230, 255, 242),
      icon: "💡",
      label: "Tip",
    ),
    important: (
      border: rgb(204, 0, 0),
      bg: rgb(255, 230, 230),
      icon: "❗",
      label: "Important",
    ),
  )

  let style = styles.at(kind)
  let display-title = if title != none { title } else { style.label }

  block(
    width: 100%,
    fill: style.bg,
    stroke: (left: 4pt + style.border),
    radius: 4pt,
    inset: 10pt,
    above: 1em,
    below: 1em,
  )[
    #set text(weight: "bold")
    #style.icon #display-title
    #linebreak()
    #set text(weight: "regular")
    #body
  ]
}

#let note(body) = admonition(kind: "note", body)
#let warning(body) = admonition(kind: "warning", body)
#let tip(body) = admonition(kind: "tip", body)
#let important(body) = admonition(kind: "important", body)

// Code listing with caption
#let code-listing(caption: "", language: "rust", body) = {
  figure(caption: caption, kind: "listing")[
    #block(fill: rgb(245, 245, 245), inset: 15pt, radius: 4pt, width: 100%)[
      #set text(size: 9pt)
      #raw(body, lang: language)
    ]
  ]
}

// Reference to an ADR document in the sibling `adrs/` directory.
// `num`: zero-padded ADR number (e.g. "015"), `slug`: filename suffix.
#let adr-ref(num: str, slug: str, title: str) = {
  link("../adrs/ADR-" + num + "-" + slug + ".md")[ADR-#num: #title]
}

// Reference a PlantUML-rendered diagram stored in `diagrams/`.
// SVGs are generated by build.sh from `../diagrams/*.puml` before compilation.
#let diagram(name, caption: none, width: 100%) = {
  figure(caption: caption)[
    #image("diagrams/" + name + ".svg", width: width)
  ]
}
