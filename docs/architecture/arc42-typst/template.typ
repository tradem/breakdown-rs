// arc42 Typst Template for Architecture Documentation
// Inspired by: https://arc42.org/template/

#let doc(
  title: str,
  subtitle: str,
  version: str,
  date: str,
  authors: array,
  body,
) = {
  // Document setup
  set document(title: title, author: authors.join(", "))
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

  // Text and paragraph settings
  set text(font: "Libertinus Serif", size: 11pt, lang: "en")
  set par(justify: true, leading: 0.65em)
  set linebreaks(wrap: true)

  // Heading styles
  set heading(numbering: "1.1")
  show heading: it => {
    // Add page break before top-level headings (chapters)
    if it.level == 1 {
      pagebreak(weak: true)
    }

    // Style based on level
    if it.level == 1 {
      block(
        above: 2em,
        below: 1em,
        [
          #set text(size: 24pt, weight: "bold", fill: rgb(0, 51, 102))
          #it
          #line(length: 100%, stroke: 1pt + rgb(0, 51, 102))
        ]
      )
    } else if it.level == 2 {
      block(
        above: 1.5em,
        below: 0.8em,
        [
          #set text(size: 18pt, weight: "bold", fill: rgb(0, 51, 102))
          #it
        ]
      )
    } else if it.level == 3 {
      block(
        above: 1em,
        below: 0.5em,
        [
          #set text(size: 14pt, weight: "bold")
          #it
        ]
      )
    } else {
      block(
        above: 0.8em,
        below: 0.4em,
        [
          #set text(size: 12pt, weight: "bold")
          #it
        ]
      )
    }
  }

  // Table of contents
  show outline: it => {
    set heading(numbering: none)
    it
  }

  // Code block styling
  show raw: it => {
    if it.block {
      block(
        fill: rgb(245, 245, 245),
        inset: 10pt,
        radius: 4pt,
        width: 100%,
        [
          #set text(font: "JetBrains Mono", size: 9pt)
          #it
        ]
      )
    } else {
      it
    }
  }

  // Link styling
  show link: it => {
    set text(fill: rgb(0, 102, 204))
    it
  }

  // List styling
  set enum(indent: 1em)
  set list(indent: 1em)

  // Table styling
  set table(
    stroke: (x, y) => (
      left: if x > 0 { 0.5pt + gray },
      top: if y > 0 { 0.5pt + gray },
    ),
    align: (x, y) => (
      if x == 0 { left } else { left }
    ),
  )
  show table.cell: it => {
    if it.y == 0 {
      strong(it)
    } else {
      it
    }
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
        #text(size: 14pt)[
          *Authors:* \
          #authors.join(", ")
        ]
      ]

      #v(2cm)

      #text(size: 10pt, fill: gray)[
        Documentation generated with #link("https://typst.app/")[Typst] \
        Based on the #link("https://arc42.org/")[arc42] architecture documentation template
      ]
    ]
  ]

  // Table of contents
  pagebreak()
  outline(
    title: [Table of Contents],
    indent: auto,
  )

  // Main content
  body
}

// Admonition box function
#let admonition(type: "note", title: none, body) = {
  let colors = (
    note: (border: rgb(0, 102, 204), bg: rgb(230, 242, 255)),
    warning: (border: rgb(255, 153, 0), bg: rgb(255, 244, 230)),
    tip: (border: rgb(0, 153, 76), bg: rgb(230, 255, 242)),
    important: (border: rgb(204, 0, 0), bg: rgb(255, 230, 230)),
  )

  let icons = (
    note: "ℹ",
    warning: "⚠",
    tip: "💡",
    important: "❗",
  )

  let color = colors.at(type)
  let icon = icons.at(type)
  let display-title = if title != none { title } else { type.capitalize() }

  block(
    width: 100%,
    fill: color.bg,
    stroke: (left: 4pt + color.border),
    radius: 4pt,
    inset: 10pt,
    above: 1em,
    below: 1em,
  )[
    #set text(weight: "bold")
    #icon #display-title
    #linebreak()
    #set text(weight: "regular")
    #body
  ]
}

// Convenience functions for admonitions
#let note(body) = admonition(type: "note", body)
#let warning(body) = admonition(type: "warning", body)
#let tip(body) = admonition(type: "tip", body)
#let important(body) = admonition(type: "important", body)

// Code listing with caption
#let code-listing(caption: "", language: "rust", body) = {
  figure(
    caption: caption,
    kind: "listing",
  )[
    #block(
      fill: rgb(245, 245, 245),
      inset: 15pt,
      radius: 4pt,
      width: 100%,
    )[
      #set text(font: "JetBrains Mono", size: 9pt)
      #raw(body, lang: language)
    ]
  ]
}

// Architecture decision reference
#let adr-ref(num: int, title: str) = {
  link("../adrs/ADR-" + str(num).clip(2) + "-" + title.replace(" ", "-").to-lower() + ".md")[
    ADR-#str(num).clip(3): #title
  ]
}
