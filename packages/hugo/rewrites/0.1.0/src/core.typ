#import "@hugo/utils:0.1.0": *

#let outline-func(it) = context {
  if target() != "html" {
    return it
  }

  html.div(
    class: "toc",
    style: "display: none",
    collapsible([Table of Contents], it),
  )
}

#let outline-entry-func = list.item

#let h-func(it) = context {
  if target() != "html" {
    return it
  }

  let amount = it.amount.to-absolute().pt()
  html.span(
    style: "display: inline-block; width: 100%; width: " + str(amount) + "px;",
  )
}

#let v-func(it) = context {
  if target() != "html" {
    return it
  }

  let amount = it.amount.to-absolute().pt()
  html.div(
    style: "height: " + str(amount) + "px;",
  )
}

#let align-func(it) = context {
  if target() != "html" {
    return it
  }

  let (x-align, y-align) = to-alignment(it.alignment)
  let place-items = y-align + " " + x-align

  html.div(
    style: "display: grid; place-items: " + place-items + ";",
    it.body,
  )
}

// make figure and table centered by default
#let figure-func(it) = context {
  if target() != "html" {
    return it
  }

  let body = align(center, it.body)
  let caption = align(center, it.caption)
  let output = if it.kind == table {
    caption
    body
  } else {
    body
    caption
  }
  align(center, html.figure(output))
}

#let table-func(it) = context {
  if target() != "html" {
    return it
  }

  let columns = it.columns.len()
  let align = it.align
  let entries = it.children.map(c => c.body)

  let rows = int((entries.len() + columns - 1) / columns)
  let aligns = if type(align) == alignment {
    (to-alignment(align),) * columns
  } else if type(align) == array {
    // fill in last alignment if not enough
    if align.len() < columns {
      let last = to-alignment(align.last(default: left + top))
      (align.map(a => to-alignment(a)) + (last,) * columns).slice(0, columns)
    } else {
      align.map(a => to-alignment(a)).slice(0, columns)
    }
  } else {
    panic("Unsupported alignment type, please use a valid alignment or a list of alignments!")
  }

  html.table(
    for i in range(0, rows) {
      html.tr(
        for j in range(0, columns) {
          let index = i * columns + j
          let cell-func = if i == 0 { html.th } else { html.td }
          if index < entries.len() {
            let (x-align, y-align) = aligns.at(j, default: (to-alignment(left + top)))
            cell-func(
              style: "text-align: " + x-align + "; vertical-align: " + y-align + ";",
              entries.at(index),
            )
          } else {
            cell-func() // empty cell
          }
        },
      )
    },
  )
}

// make links open in new tab if it's an external link
#let link-func(it) = context {
  if target() != "html" {
    return it
  }

  let body = it.body
  let dest = it.dest
  if type(dest) != str {
    it
  } else if dest.starts-with("http") {
    body = text-colored(color.rgb("#59a4ff"), underline(body))
    html.a(body, href: dest, target: "_blank", rel: ("noopener", "noreferrer"))
  } else {
    body = text-colored(color.rgb("#c24bbc"), underline(body))
    html.a(body, href: dest)
  }
}

// equation was ignored during HTML export
#let math-equation-func(it) = context {
  if target() != "html" {
    return it
  }

  let block = it.block
  if block {
    html.figure(role: "math", style: "text-align: center;", frame(it))
  } else {
    html.span(role: "math", frame(it))
  }
}

// wrap raw content in a div/span with a class for styling
#let raw-func(it) = context {
  if target() != "html" {
    return it
  }

  let block = it.block
  if block {
    html.div(class: "typst-raw-block", it)
  } else {
    html.span(class: "typst-raw-inline", it)
  }
}

#let image-func(it) = context {
  if target() != "html" {
    return it
  }

  let alt = if it.alt != none { it.alt } else { "" }
  let src = if type(it.source) == str { it.source } else {
    panic("unsupported image source type for HTML output, please use a string!")
  }

  html.img(src: src, alt: alt, loading: "lazy")
}
