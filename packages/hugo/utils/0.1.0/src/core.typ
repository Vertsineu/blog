#import "type.typ": *

#let frame(body) = {
  // tag a typst-frame class for styling
  // although html.frame automatically add a typst-frame class,
  // we still wrap it in a div to make sure the frame is properly sized and styled
  html.div(class: "typst-frame", html.frame(body))
}

#let align(alignment, body) = {
  let (x-align, y-align) = to-alignment(alignment)
  let place-items = y-align + " " + x-align

  html.div(
    style: "display: grid; place-items: " + place-items + ";",
    body
  )
}

#let h(len) = {
  len = to-length(len)

  context html.span(
    style: "display: inline-block; width: 100%; width: " + str(len.to-absolute().pt()) + "px;",
  )
}

#let v(len) = {
  len = to-length(len)

  context html.div(
    style: "height: " + str(len.to-absolute().pt()) + "px;",
  )
}

#let table(columns: 1, align: left + top, ..entries) = {
  let entries = entries.pos()
  let rows = int((entries.len() + columns - 1) / columns)
  let aligns = if type(align) == alignment {
    (to-alignment(align), ) * columns
  } else if type(align) == array {
    // fill in last alignment if not enough
    if align.len() < columns {
      let last = to-alignment(align.last(default: left + top))
      (align.map(a => to-alignment(a)) + (last, ) * columns).slice(0, columns)
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
              entries.at(index)
            )
          } else {
            cell-func() // empty cell
          }
        }
      )
    }
  )
}

#let text-colored(color, body) = {
  color = to-color(color)

  html.span(style: "color: " + str(color) + ";", body)
}
