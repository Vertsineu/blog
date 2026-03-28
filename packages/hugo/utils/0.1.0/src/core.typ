#let align(alignment, body) = {
  let text-alignment = if alignment == center {
    "center"
  } else if alignment == left {
    "left"
  } else if alignment == right {
    "right"
  } else {
    panic("Unsupported alignment, please use center, left or right!")
  }

  let justify-content = if alignment == center {
    "center"
  } else if alignment == left {
    "flex-start"
  } else {
    "flex-end"
  }

  html.div(
    style: "display: flex; width: 100%; justify-content: " + justify-content + ";",
    html.div(
      style: "width: fit-content; max-width: 100%; text-align: " + text-alignment + ";",
      body,
    ),
  )
}

#let colored(color, body) = {
  let pre-defined = dictionary(std)
    .pairs()
    .filter(((key, value)) => type(value) == std.color)
    .filter(((key, value)) => value == color)
    .map(((key, value)) => key)

  let color = if pre-defined.len() > 0 {
    pre-defined.first()
  } else {
    color
  }

  html.span(style: "color: " + str(color) + ";", body)
}
