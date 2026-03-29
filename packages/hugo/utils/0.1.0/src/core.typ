#let frame = html.frame

#let to-length(value) = {
  if type(value) == length {
    str(value)
  } else if type(value) == int {
    str(value) + "pt"
  } else if type(value) == float {
    str(value) + "pt"
  } else {
    none
  }
}

// support: place-items, text-align, vertical-align, etc.
#let to-alignment(alignment) = {
  if type(alignment) != std.alignment {
    panic("Unsupported alignment type, please use a valid alignment!")
  }

  let x-align = alignment.x
  x-align = if x-align == center {
    "center"
  } else if x-align == left {
    "start"
  } else if x-align == right {
    "end"
  } else if x-align == start {
    "start"
  } else if x-align == end {
    "end"
  } else {
    "start" // fallback to start if none
  }

  let y-align = alignment.y
  y-align = if y-align == top {
    "start"
  } else if y-align == horizon {
    "center"
  } else if y-align == bottom {
    "end"
  } else {
    "start" // fallback to start if none
  }

  (x-align, y-align)
}

#let to-color(color) = {
  if type(color) != std.color {
    panic("Unsupported color type, please use a valid color!")
  }

  color.to-hex()
}

#let text-colored(color, body) = {
  color = to-color(color)

  html.span(style: "color: " + str(color) + ";", body)
}
